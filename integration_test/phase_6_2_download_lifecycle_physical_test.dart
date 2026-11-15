import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempBaseDir;
  late CustomAudioStorageService storageService;
  HttpServer? mockServer;
  String? mockServerBaseUrl;

  // 64 KB of deterministic audio payload
  final testAudioBytes = Uint8List.fromList(List<int>.generate(65536, (i) => (i * 7) % 256));
  final testAudioSha256 = sha256.convert(testAudioBytes).toString().toLowerCase();

  final sampleEntry = AdhanCatalogEntry(
    id: 'remote:makkah_ali',
    sheikhName: 'الشيخ علي جابر',
    audioType: AdhanAudioType.general,
    displayName: 'أذان مكة المكرمة',
    durationSeconds: 72,
    objectKey: 'audio/makkah_ali.mp3',
    fileSizeBytes: testAudioBytes.length,
    sha256: testAudioSha256,
  );

  final secondEntry = AdhanCatalogEntry(
    id: 'remote:madinah_fajr',
    sheikhName: 'الشيخ السريحي',
    audioType: AdhanAudioType.fajr,
    displayName: 'أذان المدينة',
    durationSeconds: 90,
    objectKey: 'audio/madinah_fajr.mp3',
    fileSizeBytes: testAudioBytes.length,
    sha256: testAudioSha256,
  );

  setUp(() async {
    HttpOverrides.global = null;
    tempBaseDir = await Directory.systemTemp.createTemp('hafiz_download_test_');
    storageService = CustomAudioStorageService(
      docsDirProvider: () async => tempBaseDir,
    );
  });

  tearDown(() async {
    await mockServer?.close(force: true);
    mockServer = null;
    mockServerBaseUrl = null;
    if (await tempBaseDir.exists()) {
      await tempBaseDir.delete(recursive: true);
    }
  });

  group('Phase 6.2 — Download Lifecycle Physical & Integration Verification', () {
    test('E2E-06 [Happy Path Download & Atomic Promotion]: Streams bytes, displays progress, verifies SHA-256, promotes to adhan_sounds/', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        if (request.uri.path == '/${sampleEntry.objectKey}') {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = testAudioBytes.length;
          request.response.statusCode = HttpStatus.ok;

          // Stream in chunks of 16 KB with small pauses
          const chunkSize = 16384;
          for (int i = 0; i < testAudioBytes.length; i += chunkSize) {
            final end = (i + chunkSize < testAudioBytes.length) ? i + chunkSize : testAudioBytes.length;
            request.response.add(testAudioBytes.sublist(i, end));
            await request.response.flush();
            await Future.delayed(const Duration(milliseconds: 10));
          }
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final progressEvents = <DownloadStatus>[];
      final subscription = downloadService.watchTask(sampleEntry.id).listen((task) {
        progressEvents.add(task.status);
      });

      final result = await downloadService.downloadAudio(sampleEntry);
      await subscription.cancel();

      expect(result.isRight(), isTrue);
      final customSource = result.getOrElse(() => throw Exception());
      expect(customSource.id, equals('custom:${sampleEntry.id}'));
      expect(customSource.fileSize, equals(testAudioBytes.length));

      // Verify physical file on disk
      final storageDir = await storageService.getStorageDirectory();
      final expectedFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final targetFile = File(p.join(storageDir.path, expectedFileName));

      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), equals(testAudioBytes.length));

      final promotedHash = (await sha256.bind(targetFile.openRead()).first).toString().toLowerCase();
      expect(promotedHash, equals(testAudioSha256));

      // Verify staging .tmp file was cleaned up
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }

      // Verify progress transitions
      expect(progressEvents, contains(DownloadStatus.downloading));
      expect(progressEvents, contains(DownloadStatus.completed));
    });

    test('E2E-07 [Mid-Stream Cancellation]: Cancelling active download halts stream, cleans staging .tmp, and releases lock', () async {
      final streamPausedCompleter = Completer<void>();

      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = testAudioBytes.length;
        request.response.statusCode = HttpStatus.ok;

        // Send first chunk (16 KB)
        request.response.add(testAudioBytes.sublist(0, 16384));
        await request.response.flush();

        // Pause to allow mid-flight cancellation
        await streamPausedCompleter.future;

        try {
          request.response.add(testAudioBytes.sublist(16384));
          await request.response.close();
        } catch (_) {}
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final taskCompleter = Completer<void>();
      final sub = downloadService.watchTask(sampleEntry.id).listen((task) {
        if (task.status == DownloadStatus.downloading && task.progress.receivedBytes > 0) {
          if (!taskCompleter.isCompleted) taskCompleter.complete();
        }
      });

      // Start download in background
      final downloadFuture = downloadService.downloadAudio(sampleEntry);

      // Wait until bytes are actively flowing
      await taskCompleter.future;
      await sub.cancel();

      // Trigger mid-stream cancellation
      await downloadService.cancelDownload(sampleEntry.id);
      streamPausedCompleter.complete();

      final result = await downloadFuture;
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadCancelledFailure>()),
        (_) => fail('Should have failed with cancellation'),
      );

      // Verify staging .tmp file was deleted in finally block
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }

      // Verify single-task lock was released by starting another download immediately
      expect(downloadService.getActiveTasks(), isEmpty);
    });

    test('E2E-08 [Network Drop & Failure Recovery]: Abrupt socket disconnection cleans staging .tmp and emits failure', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = testAudioBytes.length;
        request.response.statusCode = HttpStatus.ok;

        // Send a few bytes then abruptly kill the server socket connection
        request.response.add(testAudioBytes.sublist(0, 4096));
        await request.response.flush();
        await Future.delayed(const Duration(milliseconds: 10));

        // Abrupt server termination mid-stream
        await mockServer?.close(force: true);
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(sampleEntry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadNetworkFailure>()),
        (_) => fail('Expected network failure on socket disconnect'),
      );

      // Verify no orphan .tmp files left behind
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }
    });

    test('E2E-09 [Single-Task Concurrency Serialization]: Concurrent download request is rejected synchronously', () async {
      final serverHangCompleter = Completer<void>();

      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = testAudioBytes.length;
        request.response.statusCode = HttpStatus.ok;
        await serverHangCompleter.future;
        request.response.add(testAudioBytes);
        await request.response.close();
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      // Start Task 1
      final task1Future = downloadService.downloadAudio(sampleEntry);

      // Immediately attempt Task 2 concurrently
      final task2Result = await downloadService.downloadAudio(secondEntry);

      expect(task2Result.isLeft(), isTrue);
      task2Result.fold(
        (failure) => expect(failure, isA<AudioDownloadConcurrencyFailure>()),
        (_) => fail('Task 2 should have been rejected immediately by single-task mutex'),
      );

      // Unblock Task 1 to complete normally
      serverHangCompleter.complete();
      final task1Result = await task1Future;
      expect(task1Result.isRight(), isTrue);
    });

    test('E2E-10 [Corrupt Existing File Healing]: Detects corrupt existing file with same name, deletes it, and re-downloads fresh', () async {
      final storageDir = await storageService.getStorageDirectory();
      final expectedFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final targetFile = File(p.join(storageDir.path, expectedFileName));

      // Intentionally create a corrupt 0-byte or corrupted content file at target path
      await targetFile.writeAsString('corrupt_audio_payload');

      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = testAudioBytes.length;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(testAudioBytes);
        await request.response.close();
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(sampleEntry);

      expect(result.isRight(), isTrue);
      // Verify file was healed with valid payload
      expect(await targetFile.length(), equals(testAudioBytes.length));
      final healedHash = (await sha256.bind(targetFile.openRead()).first).toString().toLowerCase();
      expect(healedHash, equals(testAudioSha256));
    });
  });
}
