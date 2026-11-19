import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late QuranAudioStorageService storageService;
  late BaseQuranAudioLocalDataSource localDataSource;
  late SharedPreferences prefs;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('download_service_test_');
    storageService = QuranAudioStorageService(
      customBaseDirectoryProvider: () => testDir,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    final db = QuranAudioDatabase.inMemory();
    await db.init();
    localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('QuranAudioDownloadService Fresh Download Pipeline (QA.5 Phase 5.4)', () {
    test('downloads entire Surah track with identity encoding, SHA-256 verification, and promotion', () async {
      final payload = List.generate(1000, (i) => i % 256);
      Map<String, String>? capturedHeaders;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        capturedHeaders = request.headers;
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'etag': '"strong-etag-1000"',
              'content-length': '1000',
              'date': 'Wed, 21 Oct 2026 07:28:05 GMT',
              'last-modified': 'Wed, 21 Oct 2026 07:28:00 GMT',
            },
          );
        }

        return http.StreamedResponse(
          Stream.value(payload),
          200,
          headers: {
            'etag': '"strong-etag-1000"',
            'content-length': '1000',
          },
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final progressEvents = <DownloadProgress>[];
      final completer = Completer<void>();

      service.downloadSurah(
        surahNumber: 1,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/1.mp3',
        expectedTotalBytes: 1000,
      ).listen(
        (p) {
          progressEvents.add(p);
          if (p.isCompleted) completer.complete();
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 5));

      // 1. Invariant: Mandatory Accept-Encoding: identity
      expect(capturedHeaders?['Accept-Encoding'], 'identity');

      // 2. Progression verification
      expect(progressEvents.any((p) => p.status == AudioDownloadStatus.downloading), isTrue);
      expect(progressEvents.any((p) => p.status == AudioDownloadStatus.verifying), isTrue);
      expect(progressEvents.last.status, AudioDownloadStatus.completed);
      expect(progressEvents.last.downloadedBytes, 1000);
      expect(progressEvents.last.progressPercentage, 100);

      // 3. Physical destination file exists and is valid
      final destFile = await storageService.resolveSurahFile(1, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), 1000);

      // 4. DB Record finalized
      final dbRecord = await localDataSource.getDownloadRecord(1, '7');
      expect(dbRecord, isNotNull);
      expect(dbRecord!.status, AudioDownloadStatus.completed);
      expect(dbRecord.actualSizeBytes, 1000);
      expect(dbRecord.transferIntegrityVerified, isTrue);
      expect(dbRecord.sha256, isNotNull);
      expect(dbRecord.completedAt, isNotNull);

      service.dispose();
    });
  });

  group('HTTP 206 Range Resumption & Strong Validator Inspection (Rev 7 Contract B1-5 & C1-1)', () {
    test('successfully resumes partial download using Strong ETag and HTTP 206', () async {
      // 1. Create partial staging file with first 400 bytes
      final stagingDir = await storageService.getStagingDirectory();
      final stagingFile = File(p.join(stagingDir.path, 'dl_7_002.tmp'));
      final firstPart = List.generate(400, (i) => i % 256);
      await stagingFile.writeAsBytes(firstPart);

      final secondPart = List.generate(600, (i) => (i + 400) % 256);
      String? capturedRangeHeader;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'etag': '"strong-etag-resumable"',
              'content-length': '1000',
            },
          );
        }

        capturedRangeHeader = request.headers['Range'];

        return http.StreamedResponse(
          Stream.value(secondPart),
          206,
          headers: {
            'etag': '"strong-etag-resumable"',
            'content-range': 'bytes 400-999/1000', // C1-1 denominator = 1000
            'content-length': '600',
          },
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final completer = Completer<void>();
      final events = <DownloadProgress>[];

      service.downloadSurah(
        surahNumber: 2,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/2.mp3',
        expectedTotalBytes: 1000,
      ).listen(
        (p) {
          events.add(p);
          if (p.isCompleted) completer.complete();
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 5));

      // Assert Range request sent for remaining bytes
      expect(capturedRangeHeader, 'bytes=400-');

      // Final destination promoted and contains all 1000 bytes
      final destFile = await storageService.resolveSurahFile(2, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), 1000);

      final fullPayload = await destFile.readAsBytes();
      expect(fullPayload.length, 1000);
      expect(fullPayload.sublist(0, 400), firstPart);
      expect(fullPayload.sublist(400, 1000), secondPart);

      service.dispose();
    });

    test('restarts from byte 0 if origin validator is Weak ETag (W/)', () async {
      // 1. Partial staging file with 300 bytes
      final stagingDir = await storageService.getStagingDirectory();
      final stagingFile = File(p.join(stagingDir.path, 'dl_7_003.tmp'));
      await stagingFile.writeAsBytes(List.generate(300, (i) => i));

      String? capturedRangeHeader;
      final fullPayload = List.generate(1000, (i) => (i * 2) % 256);

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          // Server provides Weak ETag
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'etag': 'W/"weak-validator-123"',
              'content-length': '1000',
            },
          );
        }

        capturedRangeHeader = request.headers['Range'];

        return http.StreamedResponse(
          Stream.value(fullPayload),
          200,
          headers: {
            'etag': 'W/"weak-validator-123"',
            'content-length': '1000',
          },
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final completer = Completer<void>();
      service.downloadSurah(
        surahNumber: 3,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/3.mp3',
        expectedTotalBytes: 1000,
      ).listen(
        (p) {
          if (p.isCompleted) completer.complete();
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 5));

      // Invariant: Range resumption was FORBIDDEN; started clean from byte 0
      expect(capturedRangeHeader, isNull);

      final destFile = await storageService.resolveSurahFile(3, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), 1000);

      service.dispose();
    });
  });

  group('Download Pause, Cancel, and Error Handling (QA.5 Phase 5.4)', () {
    test('pausing download flushes stream and records paused state in SQLite', () async {
      final controller = StreamController<List<int>>();

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'content-length': '5000'},
          );
        }
        return http.StreamedResponse(controller.stream, 200, headers: {'content-length': '5000'});
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final pauseCompleter = Completer<void>();

      service.downloadSurah(
        surahNumber: 4,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/4.mp3',
      ).listen((p) {
        if (p.status == AudioDownloadStatus.paused) {
          pauseCompleter.complete();
        }
      });

      // Feed first chunk
      controller.add(List.filled(500, 1));
      await Future.delayed(const Duration(milliseconds: 50));

      // Request pause
      await service.pauseDownload(4, '7');

      await pauseCompleter.future.timeout(const Duration(seconds: 3));

      // Verify DB record
      final dbRecord = await localDataSource.getDownloadRecord(4, '7');
      expect(dbRecord, isNotNull);
      expect(dbRecord!.status, AudioDownloadStatus.paused);
      expect(dbRecord.actualSizeBytes, 500);

      service.dispose();
      await controller.close();
    });

    test('cancelling download aborts stream and records cancelled state', () async {
      final controller = StreamController<List<int>>();

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(const Stream.empty(), 200);
        }
        return http.StreamedResponse(controller.stream, 200);
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final cancelCompleter = Completer<void>();

      service.downloadSurah(
        surahNumber: 5,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/5.mp3',
      ).listen((p) {
        if (p.status == AudioDownloadStatus.cancelled) {
          cancelCompleter.complete();
        }
      });

      controller.add(List.filled(200, 2));
      await Future.delayed(const Duration(milliseconds: 50));

      await service.cancelDownload(5, '7');
      await cancelCompleter.future.timeout(const Duration(seconds: 3));

      final record = await localDataSource.getDownloadRecord(5, '7');
      expect(record, isNotNull);
      expect(record!.status, AudioDownloadStatus.cancelled);

      service.dispose();
      await controller.close();
    });

    test('detects truncated stream when received bytes do not match Content-Length', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(const Stream.empty(), 200, headers: {'content-length': '1000'});
        }
        // Prematurely end stream at 400 bytes instead of 1000
        return http.StreamedResponse(
          Stream.value(List.filled(400, 0)),
          200,
          headers: {'content-length': '1000'},
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final failCompleter = Completer<void>();

      service.downloadSurah(
        surahNumber: 6,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/6.mp3',
        expectedTotalBytes: 1000,
      ).listen((p) {
        if (p.status == AudioDownloadStatus.failed) {
          failCompleter.complete();
        }
      });

      await failCompleter.future.timeout(const Duration(seconds: 5));

      final record = await localDataSource.getDownloadRecord(6, '7');
      expect(record, isNotNull);
      expect(record!.status, AudioDownloadStatus.failed);
      expect(record.lastError, contains('truncated'));

      service.dispose();
    });

    test('pausing and then resuming downloads remaining slice via HTTP 206 Range to completion', () async {
      final chunk1 = List.generate(500, (i) => i % 256);
      final chunk2 = List.generate(500, (i) => (i + 500) % 256);
      final fullPayload = [...chunk1, ...chunk2];

      final stream1Controller = StreamController<List<int>>();
      String? secondRequestRangeHeader;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'content-length': '1000'},
          );
        }

        final range = request.headers['Range'];
        if (range != null) {
          secondRequestRangeHeader = range;
          // HTTP 206 Partial Content
          return http.StreamedResponse(
            Stream.value(chunk2),
            206,
            headers: {
              'content-range': 'bytes 500-999/1000',
              'content-length': '500',
            },
          );
        }

        // First attempt (byte 0)
        return http.StreamedResponse(
          stream1Controller.stream,
          200,
          headers: {'content-length': '1000'},
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final pauseCompleter = Completer<void>();
      final sub1 = service.downloadSurah(
        surahNumber: 10,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/10.mp3',
        expectedTotalBytes: 1000,
      ).listen((p) {
        if (p.status == AudioDownloadStatus.paused) {
          if (!pauseCompleter.isCompleted) pauseCompleter.complete();
        }
      });

      // Send chunk 1 and pause
      stream1Controller.add(chunk1);
      await Future.delayed(const Duration(milliseconds: 50));
      await service.pauseDownload(10, '7');
      await pauseCompleter.future.timeout(const Duration(seconds: 3));
      await sub1.cancel();
      await stream1Controller.close();

      // Verify paused in database with 500 bytes
      final pausedRecord = await localDataSource.getDownloadRecord(10, '7');
      expect(pausedRecord?.status, AudioDownloadStatus.paused);
      expect(pausedRecord?.actualSizeBytes, 500);

      // Now RESUME download
      final resumeCompleter = Completer<void>();
      final sub2 = service.downloadSurah(
        surahNumber: 10,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/10.mp3',
        expectedTotalBytes: 1000,
      ).listen((p) {
        if (p.status == AudioDownloadStatus.completed) {
          if (!resumeCompleter.isCompleted) resumeCompleter.complete();
        }
      });

      await resumeCompleter.future.timeout(const Duration(seconds: 4));
      await sub2.cancel();

      // Verify second request used HTTP 206 Range resumption from byte 500
      expect(secondRequestRangeHeader, 'bytes=500-');

      // Verify completed file on disk matches full payload
      final destFile = await storageService.resolveSurahFile(10, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), 1000);
      expect(await destFile.readAsBytes(), fullPayload);

      service.dispose();
    });

    test('cancelling download purges staging file and allows clean restart from byte 0', () async {
      final stream1Controller = StreamController<List<int>>();
      final fullPayload = List.generate(800, (i) => i % 256);
      String? secondRequestRangeHeader;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'content-length': '800'},
          );
        }

        secondRequestRangeHeader = request.headers['Range'];

        if (stream1Controller.isClosed) {
          return http.StreamedResponse(
            Stream.value(fullPayload),
            200,
            headers: {'content-length': '800'},
          );
        }

        return http.StreamedResponse(
          stream1Controller.stream,
          200,
          headers: {'content-length': '800'},
        );
      });

      final service = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final cancelCompleter = Completer<void>();
      final sub1 = service.downloadSurah(
        surahNumber: 11,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/11.mp3',
        expectedTotalBytes: 800,
      ).listen((p) {
        if (p.status == AudioDownloadStatus.cancelled) {
          if (!cancelCompleter.isCompleted) cancelCompleter.complete();
        }
      });

      stream1Controller.add(List.filled(300, 1));
      await Future.delayed(const Duration(milliseconds: 50));

      await service.cancelDownload(11, '7');
      await cancelCompleter.future.timeout(const Duration(seconds: 3));
      await sub1.cancel();
      await stream1Controller.close();

      // Verify staging file was physically deleted
      final stagingDir = await storageService.getStagingDirectory();
      final stagingFile = File(p.join(stagingDir.path, 'dl_7_011.tmp'));
      expect(await stagingFile.exists(), isFalse);

      // Verify DB record is cancelled with actualSizeBytes 0
      final cancelledRecord = await localDataSource.getDownloadRecord(11, '7');
      expect(cancelledRecord?.status, AudioDownloadStatus.cancelled);
      expect(cancelledRecord?.actualSizeBytes, 0);

      // Now start fresh download for same surah
      final restartCompleter = Completer<void>();
      final sub2 = service.downloadSurah(
        surahNumber: 11,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/11.mp3',
        expectedTotalBytes: 800,
      ).listen((p) {
        if (p.status == AudioDownloadStatus.completed) {
          if (!restartCompleter.isCompleted) restartCompleter.complete();
        }
      });

      await restartCompleter.future.timeout(const Duration(seconds: 4));
      await sub2.cancel();

      // Invariant: Second request did NOT use Range; it started clean from byte 0
      expect(secondRequestRangeHeader, isNull);

      final destFile = await storageService.resolveSurahFile(11, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), 800);

      service.dispose();
    });
  });
}
