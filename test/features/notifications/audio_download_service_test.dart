import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';

const String kTestBaseUrl = 'https://audio.example.com';

AdhanCatalogEntry _createTestEntry({
  String id = 'remote:test_sheikh_fajr',
  String objectKey = 'audio/test.mp3',
  required Uint8List bytes,
}) {
  final hash = sha256.convert(bytes).toString();
  return AdhanCatalogEntry(
    id: id,
    sheikhName: 'الشيخ التجريبي',
    audioType: AdhanAudioType.fajr,
    displayName: 'أذان الفجر التجريبي',
    durationSeconds: 60,
    objectKey: objectKey,
    fileSizeBytes: bytes.length,
    sha256: hash,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempTestDir;
  late CustomAudioStorageService storageService;

  setUp(() async {
    tempTestDir = await Directory.systemTemp.createTemp('audio_download_test_');
    storageService = CustomAudioStorageService(
      docsDirProvider: () async => tempTestDir,
    );
  });

  tearDown(() async {
    if (await tempTestDir.exists()) {
      await tempTestDir.delete(recursive: true);
    }
  });

  group('AudioDownloadServiceImpl — Happy Path & File Verification', () {
    test('Successful download, stream, SHA-256 verification, and atomic promotion', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 50, (i) => i % 256));
      final entry = _createTestEntry(bytes: audioBytes);

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(
          Stream.value(audioBytes),
          200,
          contentLength: audioBytes.length,
        );
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final taskStates = <DownloadStatus>[];
      final sub = service.watchTask(entry.id).listen((task) {
        taskStates.add(task.status);
      });

      final result = await service.downloadAudio(entry);

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected successful download'),
        (source) {
          expect(source.fileSize, equals(audioBytes.length));
          expect(source.localRelativePath, contains('remote_test_sheikh_fajr_'));
        },
      );

      // Verify task lifecycle progression
      expect(taskStates, contains(DownloadStatus.downloading));
      expect(taskStates, contains(DownloadStatus.verifying));
      expect(taskStates, contains(DownloadStatus.promoting));
      expect(taskStates, contains(DownloadStatus.completed));

      // Verify promoted physical file exists on disk
      final storageDir = await storageService.getStorageDirectory();
      final targetName = AudioDownloadServiceImpl.buildTargetFileName(entry);
      final promotedFile = File('${storageDir.path}/$targetName');
      expect(await promotedFile.exists(), isTrue);
      expect(await promotedFile.length(), equals(audioBytes.length));

      // Verify temp folder is clean
      final tempDir = Directory('${storageDir.path}/.tmp');
      if (await tempDir.exists()) {
        expect(tempDir.listSync(), isEmpty);
      }

      await sub.cancel();
      await service.dispose();
    });

    test('Existing file with valid full SHA-256 skips download and returns source', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 10, (i) => (i * 3) % 256));
      final entry = _createTestEntry(bytes: audioBytes);

      // Pre-seed storage directory with verified target file
      final storageDir = await storageService.getStorageDirectory();
      final targetName = AudioDownloadServiceImpl.buildTargetFileName(entry);
      final existingFile = File('${storageDir.path}/$targetName');
      await existingFile.writeAsBytes(audioBytes);

      var networkRequested = false;
      final mockClient = MockClient((request) async {
        networkRequested = true;
        return http.Response('', 500);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(networkRequested, isFalse, reason: 'Must skip download when valid file exists');
      expect(result.isRight(), isTrue);

      await service.dispose();
    });

    test('Existing file with corrupted hash is deleted and cleanly re-downloaded', () async {
      final validBytes = Uint8List.fromList(List.generate(1024 * 10, (i) => i % 256));
      final entry = _createTestEntry(bytes: validBytes);

      // Pre-seed storage directory with corrupt file (different bytes, same name)
      final storageDir = await storageService.getStorageDirectory();
      final targetName = AudioDownloadServiceImpl.buildTargetFileName(entry);
      final existingFile = File('${storageDir.path}/$targetName');
      await existingFile.writeAsBytes(Uint8List(validBytes.length)); // Zeroes -> different hash

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(
          Stream.value(validBytes),
          200,
          contentLength: validBytes.length,
        );
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isRight(), isTrue);
      // Verify re-downloaded file matches valid hash
      final updatedBytes = await existingFile.readAsBytes();
      expect(sha256.convert(updatedBytes).toString(), equals(entry.sha256));

      await service.dispose();
    });
  });

  group('AudioDownloadServiceImpl — Mandatory Failure Scenarios', () {
    test('Network disconnect during streaming cleans up temp file', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 20, (i) => i % 256));
      final entry = _createTestEntry(bytes: audioBytes);

      final controller = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, stream) async {
        // Send partial chunk then emit network error
        controller.add(audioBytes.sublist(0, 1024));
        controller.addError(const SocketException('Connection aborted by host'));
        return http.StreamedResponse(controller.stream, 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadNetworkFailure>()),
        (r) => fail('Expected failure'),
      );

      // Verify temp folder is cleaned up
      final storageDir = await storageService.getStorageDirectory();
      final tempDir = Directory('${storageDir.path}/.tmp');
      if (await tempDir.exists()) {
        expect(tempDir.listSync(), isEmpty);
      }

      await service.dispose();
    });

    test('HTTP 404 returns AudioDownloadNetworkFailure and cleans up', () async {
      final audioBytes = Uint8List.fromList([1, 2, 3]);
      final entry = _createTestEntry(bytes: audioBytes);

      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadNetworkFailure>()),
        (r) => fail('Expected failure'),
      );

      await service.dispose();
    });

    test('HTTP redirect is strictly blocked with AudioDownloadSecurityFailure', () async {
      final audioBytes = Uint8List.fromList([1, 2, 3]);
      final entry = _createTestEntry(bytes: audioBytes);

      final mockClient = MockClient((request) async {
        return http.Response('', 302, headers: {'location': 'https://insecure.com/audio.mp3'});
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadSecurityFailure>()),
        (r) => fail('Expected failure'),
      );

      await service.dispose();
    });

    test('Size mismatch: fewer bytes received than metadata throws AudioDownloadSizeMismatchFailure', () async {
      final expectedBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final actualSentBytes = expectedBytes.sublist(0, 500); // 500 instead of 1000
      final entry = _createTestEntry(bytes: expectedBytes);

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(Stream.value(actualSentBytes), 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<AudioDownloadSizeMismatchFailure>());
          final mismatch = failure as AudioDownloadSizeMismatchFailure;
          expect(mismatch.actualBytes, equals(500));
          expect(mismatch.expectedBytes, equals(1000));
        },
        (r) => fail('Expected size mismatch failure'),
      );

      // Verify temp file deleted and no target file created
      final storageDir = await storageService.getStorageDirectory();
      final targetFile = File('${storageDir.path}/${AudioDownloadServiceImpl.buildTargetFileName(entry)}');
      expect(await targetFile.exists(), isFalse);

      await service.dispose();
    });

    test('Size mismatch: more bytes sent than metadata aborts stream immediately', () async {
      final expectedBytes = Uint8List.fromList(List.generate(500, (i) => i % 256));
      final oversizedBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final entry = _createTestEntry(bytes: expectedBytes);

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(Stream.value(oversizedBytes), 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadSizeMismatchFailure>()),
        (r) => fail('Expected size mismatch failure'),
      );

      await service.dispose();
    });

    test('File size > 30 MB aborts stream with AudioDownloadOversizedFailure', () async {
      final entry = AdhanCatalogEntry(
        id: 'remote:huge_file',
        sheikhName: 'شيخ',
        audioType: AdhanAudioType.general,
        displayName: 'أذان ضخم',
        durationSeconds: 100,
        objectKey: 'audio/huge.mp3',
        fileSizeBytes: 35 * 1024 * 1024,
        sha256: 'a' * 64,
      );

      // Stream chunks that exceed 30MB
      final chunk = Uint8List(1024 * 1024); // 1 MB chunk
      Stream<List<int>> generateHugeStream() async* {
        for (int i = 0; i < 32; i++) {
          yield chunk;
        }
      }

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(generateHugeStream(), 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadOversizedFailure>()),
        (r) => fail('Expected oversized failure'),
      );

      await service.dispose();
    });

    test('SHA-256 mismatch deletes temp file and refuses promotion', () async {
      final actualBytes = Uint8List.fromList(List.generate(1000, (i) => 42));
      // Create entry with matching size but DIFFERENT sha256
      final entry = AdhanCatalogEntry(
        id: 'remote:mismatch_test',
        sheikhName: 'شيخ',
        audioType: AdhanAudioType.general,
        displayName: 'أذان تالف الهاش',
        durationSeconds: 60,
        objectKey: 'audio/mismatch.mp3',
        fileSizeBytes: actualBytes.length,
        sha256: '0' * 64, // Different hash
      );

      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(Stream.value(actualBytes), 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await service.downloadAudio(entry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<AudioDownloadIntegrityFailure>());
          final integrity = failure as AudioDownloadIntegrityFailure;
          expect(integrity.expectedHash, equals('0' * 64));
          expect(integrity.actualHash, equals(sha256.convert(actualBytes).toString()));
        },
        (r) => fail('Expected integrity failure'),
      );

      // Verify corrupted file is NEVER promoted
      final storageDir = await storageService.getStorageDirectory();
      final targetFile = File('${storageDir.path}/${AudioDownloadServiceImpl.buildTargetFileName(entry)}');
      expect(await targetFile.exists(), isFalse);

      await service.dispose();
    });

    test('Cancellation during streaming aborts stream, deletes temp, and releases mutex', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 100, (i) => i % 256));
      final entry = _createTestEntry(bytes: audioBytes);

      final chunkController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(chunkController.stream, 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      // Start download asynchronously
      final downloadFuture = service.downloadAudio(entry);

      // Send first chunk
      chunkController.add(audioBytes.sublist(0, 1024));
      await pumpEventQueue();

      // Trigger cancellation while downloading
      await service.cancelDownload(entry.id);

      final result = await downloadFuture;

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadCancelledFailure>()),
        (r) => fail('Expected cancellation failure'),
      );

      // Verify task status is cancelled
      expect(service.getTask(entry.id)!.status, equals(DownloadStatus.cancelled));

      // Verify temp folder is clean
      final storageDir = await storageService.getStorageDirectory();
      final tempDir = Directory('${storageDir.path}/.tmp');
      if (await tempDir.exists()) {
        expect(tempDir.listSync(), isEmpty);
      }

      await service.dispose();
      chunkController.close();
    });

    test('Concurrent download attempt is rejected by single-task mutex', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 50, (i) => i % 256));
      final entry1 = _createTestEntry(id: 'remote:entry_1', bytes: audioBytes);
      final entry2 = _createTestEntry(id: 'remote:entry_2', bytes: audioBytes);

      final slowController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(slowController.stream, 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      // Launch first download
      final download1Future = service.downloadAudio(entry1);
      slowController.add(audioBytes.sublist(0, 512));
      await pumpEventQueue();

      // Attempt second download concurrently
      final download2Result = await service.downloadAudio(entry2);

      expect(download2Result.isLeft(), isTrue);
      download2Result.fold(
        (failure) => expect(failure, isA<AudioDownloadConcurrencyFailure>()),
        (r) => fail('Expected concurrency failure'),
      );

      // Clean up first download
      await service.cancelDownload(entry1.id);
      await download1Future;
      await service.dispose();
      slowController.close();
    });

    test('Service disposal during active download cancels and cleans up', () async {
      final audioBytes = Uint8List.fromList(List.generate(1024 * 50, (i) => i % 256));
      final entry = _createTestEntry(bytes: audioBytes);

      final slowController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, stream) async {
        return http.StreamedResponse(slowController.stream, 200);
      });

      final service = AudioDownloadServiceImpl(
        client: mockClient,
        storageService: storageService,
        customBaseUrl: kTestBaseUrl,
      );

      final downloadFuture = service.downloadAudio(entry);
      slowController.add(audioBytes.sublist(0, 512));
      await pumpEventQueue();

      await service.dispose();

      final result = await downloadFuture;
      expect(result.isLeft(), isTrue);
      slowController.close();
    });
  });
}
