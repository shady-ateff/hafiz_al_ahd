import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempBaseDir;
  late CustomAudioStorageService storageService;
  late SharedPreferences prefs;
  HttpServer? mockServer;
  String? mockServerBaseUrl;

  final testPayload = Uint8List.fromList(List<int>.generate(32768, (i) => (i * 13) % 256));
  final validSha256 = sha256.convert(testPayload).toString().toLowerCase();

  final sampleEntry = AdhanCatalogEntry(
    id: 'remote:cairo_fajr',
    sheikhName: 'الشيخ محمد رفعت',
    audioType: AdhanAudioType.fajr,
    displayName: 'أذان فجر القاهرة النادر',
    durationSeconds: 85,
    objectKey: 'audio/cairo_fajr.mp3',
    fileSizeBytes: testPayload.length,
    sha256: validSha256,
  );

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    tempBaseDir = await Directory.systemTemp.createTemp('hafiz_atomic_test_');
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

  group('Phase 6.3 — Atomic Promotion & Integrity Physical Verification', () {
    test('E2E-11 [SHA-256 Integrity Verification]: Valid hash passes verification and promotes atomically', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = testPayload.length;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(testPayload);
        await request.response.close();
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(sampleEntry);

      expect(result.isRight(), isTrue);
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final targetFile = File(p.join(storageDir.path, targetFileName));

      expect(await targetFile.exists(), isTrue);
      final calculated = (await sha256.bind(targetFile.openRead()).first).toString().toLowerCase();
      expect(calculated, equals(validSha256));
    });

    test('E2E-12 [Bitflip Injection & Integrity Failure]: Injected stream bitflip triggers SHA mismatch and purges .tmp', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      // Corrupted payload with a single bit flipped at index 100
      final corruptedPayload = Uint8List.fromList(testPayload);
      corruptedPayload[100] = corruptedPayload[100] ^ 0x01; // Invert bit

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = corruptedPayload.length;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(corruptedPayload);
        await request.response.close();
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(sampleEntry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadIntegrityFailure>()),
        (_) => fail('Should have failed SHA-256 integrity check'),
      );

      // Verify NO promoted file exists
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final targetFile = File(p.join(storageDir.path, targetFileName));
      expect(await targetFile.exists(), isFalse);

      // Verify staging .tmp file was purged in finally block
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }
    });

    test('E2E-13 [Oversized Byte Ceiling]: Stream exceeding kRemoteAudioMaxBytes is severed immediately', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      // Large entry metadata attempting > 30 MB (481 chunks of 64KB = 31,522,816 bytes)
      const chunkSize = 65536;
      const oversizedBytes = kRemoteAudioMaxBytes + chunkSize;
      final oversizedEntry = AdhanCatalogEntry(
        id: 'remote:oversized_audio',
        sheikhName: 'شيخ',
        audioType: AdhanAudioType.general,
        displayName: 'أذان ضخم جداً',
        durationSeconds: 120,
        objectKey: 'audio/oversized.mp3',
        fileSizeBytes: oversizedBytes,
        sha256: 'f' * 64,
      );

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.contentLength = oversizedBytes;
        request.response.statusCode = HttpStatus.ok;

        // Stream until exceeding the 30 MB ceiling
        final chunk = Uint8List(chunkSize);
        int sent = 0;
        try {
          while (sent < oversizedBytes) {
            request.response.add(chunk);
            await request.response.flush();
            sent += chunk.length;
          }
          await request.response.close();
        } catch (_) {}
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(oversizedEntry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadOversizedFailure>()),
        (_) => fail('Expected AudioDownloadOversizedFailure'),
      );

      // Verify staging directory is clean
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }
    });

    test('E2E-14 [Metadata Size Mismatch Rejection]: Truncated stream is rejected and purged', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.statusCode = HttpStatus.ok;

        // Send only half the expected payload then close response cleanly
        request.response.add(testPayload.sublist(0, testPayload.length ~/ 2));
        await request.response.close();
      });

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
        customBaseUrl: mockServerBaseUrl,
      );

      final result = await downloadService.downloadAudio(sampleEntry);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AudioDownloadSizeMismatchFailure>()),
        (_) => fail('Expected AudioDownloadSizeMismatchFailure'),
      );

      // Staging file purged
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      if (await tmpDir.exists()) {
        final tmpFiles = tmpDir.listSync().whereType<File>().toList();
        expect(tmpFiles, isEmpty);
      }
    });

    test('E2E-15 [Abandoned .tmp Isolation After Process Death]: Orphaned .tmp file is classified as abandoned and excluded from active cache', () async {
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      await tmpDir.create(recursive: true);

      // Create an orphaned .tmp file simulating app killed mid-download 2 hours ago
      final orphanFile = File(p.join(tmpDir.path, 'dl_999_${DateTime.now().millisecondsSinceEpoch}.tmp'));
      await orphanFile.writeAsBytes(testPayload);

      final downloadService = AudioDownloadServiceImpl(
        client: http.Client(),
        storageService: storageService,
      );

      final storageLock = AudioStorageLock();
      final configDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);

      final storageManager = AdhanStorageManagerServiceImpl(
        storageService: storageService,
        prayerConfigDataSource: configDataSource,
        downloadService: downloadService,
        audioStorageLock: storageLock,
        prefs: prefs,
        nowProvider: () => DateTime.now().add(const Duration(hours: 2)),
      );

      final inventory = await storageManager.inspectStorage();

      // Verify orphaned file was classified properly
      expect(inventory.abandonedTmpFiles.length, equals(1));
      expect(inventory.abandonedTmpFiles.first.fileName, equals(p.basename(orphanFile.path)));
      expect(inventory.abandonedTmpFiles.first.classification, equals(StorageFileClassification.stagingTmp));
      expect(inventory.abandonedTmpFiles.first.isProtected, isFalse);

      // Strictly verify it does NOT count towards valid remote cache bytes!
      expect(inventory.remoteCacheBytes, equals(0));
      // Strictly verify it is NOT in safe eviction candidates (preview only)
      expect(inventory.evictionCandidates, isEmpty);
      // Staging bytes reflects physical storage
      expect(inventory.stagingTmpBytes, equals(testPayload.length));
    });
  });
}
