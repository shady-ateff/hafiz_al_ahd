import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/playable_audio_resolver_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';

class FakeAudioDownloadServiceForPhysicalFault implements BaseAudioDownloadService {
  final Set<String> activePrefixes;
  FakeAudioDownloadServiceForPhysicalFault({this.activePrefixes = const {}});

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(AdhanCatalogEntry entry) async =>
      Left(AudioDownloadCancelledFailure());

  @override
  Future<void> cancelDownload(String entryId) async {}

  @override
  AudioDownloadTask? getTask(String entryId) => null;

  @override
  List<AudioDownloadTask> getActiveTasks() => const [];

  @override
  Set<String> getActiveTempPrefixes() => activePrefixes;

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) => const Stream.empty();

  @override
  Future<bool> isAudioDownloaded(String entryId) async => false;

  @override
  Future<void> dispose() async {}
}

class FakeAdhanCatalogRepoForPhysicalFault implements BaseAdhanCatalogRepository {
  final AdhanCatalog catalog;
  FakeAdhanCatalogRepoForPhysicalFault(this.catalog);

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async =>
      Right(catalog);

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async => Right(catalog);

  Future<Either<AdhanCatalogFailure, AdhanCatalogEntry>> getEntry(String id) async {
    final match = catalog.entries.where((e) => e.id == id);
    if (match.isEmpty) return Left(CatalogNotFoundFailure());
    return Right(match.first);
  }

  @override
  Future<void> clearCache() async {}
}

class FakePlayableAudioResolverForPhysicalFault implements BasePlayableAudioResolver {
  @override
  Future<ResolvedPlayableAudio> resolveAudio(AudioSourceConfig source, {required bool isFajr}) async =>
      const ResolvedPlayableAudio(path: 'assets/sounds/adhan.mp3', isAsset: true, isFallback: false);

  @override
  Future<CatalogEntryResolution> resolveCatalogEntry(AdhanCatalogEntry entry) async =>
      const CatalogEntryResolution(status: AudioPlayableStatus.requiresDownload);

  @override
  Future<CustomAudioSource?> resolveLocalCustomSource(AdhanCatalogEntry entry) async => null;

  @override
  Future<bool> isAudioPlayableLocally(AudioSourceConfig source) async => true;
}

class TestAudioPlayer extends AudioPlayer {
  TestAudioPlayer() : super(playerId: 'fault_physical_player_id');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('xyz.luan/audioplayers');
  const MethodChannel globalChannel = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel eventChannel = MethodChannel('xyz.luan/audioplayers/events/fault_physical_player_id');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalChannel, (MethodCall methodCall) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannel, (MethodCall methodCall) async => null);
  });

  group('Phase 6.6 — Fault Injection & Recovery (Physical Android Verification)', () {
    late Directory tempRoot;
    late Directory storageDir;
    late CustomAudioStorageService storageService;
    late PrayerAlarmConfigLocalDataSourceImpl localDataSource;
    late BaseAudioStorageLock audioStorageLock;
    late PrayerAlarmConfigRepositoryImpl configRepo;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      tempRoot = await Directory.systemTemp.createTemp('p66_device_fault_');
      storageService = CustomAudioStorageService(
        docsDirProvider: () async => tempRoot,
      );
      storageDir = await storageService.getStorageDirectory();
      localDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      audioStorageLock = AudioStorageLock();
      configRepo = PrayerAlarmConfigRepositoryImpl(
        localDataSource: localDataSource,
        audioStorageLock: audioStorageLock,
        storageService: storageService,
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    // -------------------------------------------------------------------------
    // E2E-29: Rapid Concurrent Settings Toggle
    // -------------------------------------------------------------------------
    testWidgets('E2E-29 [Rapid Concurrent Settings Toggle]: 25 concurrent updates execute without deadlock and maintain consistency on Android device', (WidgetTester tester) async {
      // 1. Prepare valid physical custom audio files so containment check succeeds on device
      final fajrFile = File(p.join(storageDir.path, 'remote_fajr_111122223333444455556666.mp3'));
      await fajrFile.writeAsBytes(List.filled(2048, 0x11));

      final asrFile = File(p.join(storageDir.path, 'remote_asr_777788889999000011112222.mp3'));
      await asrFile.writeAsBytes(List.filled(3072, 0x22));

      final customFajrSource = CustomAudioSource(
        id: 'custom:remote:fajr',
        displayName: 'Fajr Custom',
        localRelativePath: 'adhan_sounds/remote_fajr_111122223333444455556666.mp3',
        originalFileName: 'fajr.mp3',
        fileSize: 2048,
      );

      final customAsrSource = CustomAudioSource(
        id: 'custom:remote:asr',
        displayName: 'Asr Custom',
        localRelativePath: 'adhan_sounds/remote_asr_777788889999000011112222.mp3',
        originalFileName: 'asr.mp3',
        fileSize: 3072,
      );

      const builtInAbdulbasit = BuiltInAudioSource(
        id: 'builtIn:abdulbasit',
        displayName: 'الشيخ عبد الباسط عبد الصمد',
        assetPath: 'assets/sounds/abdulbasit.mp3',
      );
      const builtInMishary = AudioSourceConfig.defaultMishary;

      // 2. Launch 25 concurrent updates targeting all 5 prayers with interleaved sources
      final futures = <Future<void>>[];
      const prayers = PrayerId.values;

      for (int i = 0; i < 25; i++) {
        final prayer = prayers[i % prayers.length];
        AudioSourceConfig chosenSource;
        final mode = i % 4;
        switch (mode) {
          case 0:
            chosenSource = prayer == PrayerId.fajr ? customFajrSource : customAsrSource;
            break;
          case 1:
            chosenSource = builtInAbdulbasit;
            break;
          case 2:
            chosenSource = builtInMishary;
            break;
          case 3:
          default:
            chosenSource = customAsrSource;
            break;
        }

        final config = PrayerAlarmConfig(
          prayerId: prayer,
          alarmType: PrayerAlarmType.alarm,
          audioSource: chosenSource,
        );

        futures.add(configRepo.saveConfig(config));
      }

      // 3. Await all 25 concurrent operations with a strict 10-second timeout guard on device
      await expectLater(
        Future.wait(futures).timeout(const Duration(seconds: 10)),
        completes,
        reason: 'Concurrent saveConfig operations must resolve cleanly without deadlock on Android device',
      );

      // 4. Verify repository consistency
      final finalConfigs = await configRepo.getConfigs();
      expect(finalConfigs.length, equals(5), reason: 'All 5 prayer configs must be present');
      for (final prayer in prayers) {
        expect(finalConfigs.containsKey(prayer), isTrue);
        final cfg = finalConfigs[prayer]!;
        expect(cfg.prayerId, equals(prayer));
        expect(cfg.audioSource, isNotNull);
      }

      // 5. Verify the lock is idle and unblocked for subsequent operations
      final probeResult = await audioStorageLock.synchronized(() async => 'LOCK_AVAILABLE_DEVICE');
      expect(probeResult, equals('LOCK_AVAILABLE_DEVICE'));
    });

    // -------------------------------------------------------------------------
    // E2E-30: Dry-Run GC Safety
    // -------------------------------------------------------------------------
    testWidgets('E2E-30 [Dry-Run GC Safety]: Abandoned staging files on Android filesystem are classified for preview only, physical GC is absent, and 0 files are unlinked', (WidgetTester tester) async {
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      await tmpDir.create(recursive: true);

      // Create 2 abandoned .tmp files older than 60 minutes
      final abandonedFile1 = File(p.join(tmpDir.path, 'dl_91_1000000.tmp'));
      await abandonedFile1.writeAsBytes(List.filled(1500, 0xAA));
      final abandonedFile2 = File(p.join(tmpDir.path, 'dl_92_2000000.tmp'));
      await abandonedFile2.writeAsBytes(List.filled(2500, 0xBB));

      // Create 1 active in-flight .tmp file
      final activeFile = File(p.join(tmpDir.path, 'dl_93_3000000.tmp'));
      await activeFile.writeAsBytes(List.filled(5000, 0xCC));

      final downloadService = FakeAudioDownloadServiceForPhysicalFault(
        activePrefixes: {'dl_93_'},
      );

      final fakeNow = DateTime.now().add(const Duration(hours: 2));
      final storageManager = AdhanStorageManagerServiceImpl(
        storageService: storageService,
        prayerConfigDataSource: localDataSource,
        downloadService: downloadService,
        audioStorageLock: audioStorageLock,
        prefs: prefs,
        nowProvider: () => fakeNow,
      );

      // 1. Inspect storage
      final inventory = await storageManager.inspectStorage(
        ageThreshold: const Duration(minutes: 60),
      );

      // 2. Verify inspection classification
      expect(inventory.abandonedTmpFiles.length, equals(2));
      expect(inventory.abandonedTmpBytes, equals(1500 + 2500));
      expect(inventory.stagingTmpBytes, equals(1500 + 2500 + 5000));
      expect(inventory.evictionCandidates.isEmpty, isTrue,
          reason: 'Abandoned tmp files must NEVER be classified as eviction candidates');

      // 3. Verify in UI cubit state
      final dummyCatalog = AdhanCatalog(
        schemaVersion: 1,
        generatedAt: DateTime.now().toIso8601String(),
        entries: [
          AdhanCatalogEntry(
            id: 'remote:makkah',
            sheikhName: 'علي ملا',
            audioType: AdhanAudioType.general,
            displayName: 'أذان مكة',
            durationSeconds: 180,
            fileSizeBytes: 2000,
            sha256: 'deadbeef11112222333344445555666677778888999900001111222233334444',
            objectKey: 'audio/makkah.mp3',
          ),
        ],
      );

      final cubit = AdhanCatalogCubit(
        catalogRepository: FakeAdhanCatalogRepoForPhysicalFault(dummyCatalog),
        downloadService: downloadService,
        storageManagerService: storageManager,
        playableAudioResolver: FakePlayableAudioResolverForPhysicalFault(),
        audioPlayer: TestAudioPlayer(),
      );

      await cubit.loadCatalog();
      await cubit.refreshStorageInventory();
      expect(cubit.state.storageInventory, isNotNull);
      expect(cubit.state.storageInventory!.abandonedTmpFiles.length, equals(2));
      expect(cubit.state.storageInventory!.abandonedTmpBytes, equals(4000));

      // 4. Verify physical disk state: all 3 tmp files exist and 0 files are unlinked
      expect(await abandonedFile1.exists(), isTrue);
      expect(await abandonedFile2.exists(), isTrue);
      expect(await activeFile.exists(), isTrue);

      await cubit.close();
    });

    // -------------------------------------------------------------------------
    // E2E-31: Symlink Traversal & Path Containment Attack
    // -------------------------------------------------------------------------
    testWidgets('E2E-31 [Symlink Traversal & Path Containment]: Path traversal strings and Linux symlink escapes on Android are strictly intercepted with zero data leakage', (WidgetTester tester) async {
      // 1. Path Traversal String Attacks on validatePathContainment
      const traversalPaths = [
        'adhan_sounds/../../sensitive.txt',
        '/sensitive.txt',
        '\\sensitive.txt',
        '../sensitive.txt',
        'adhan_sounds_backup/test.mp3',
        'secret.mp3',
      ];

      for (final badPath in traversalPaths) {
        expect(
          () => storageService.validatePathContainment(badPath),
          throwsA(isA<FileSystemException>()),
          reason: 'Path traversal attempt $badPath must throw FileSystemException',
        );
      }

      // 2. Path Traversal in PlayableAudioResolver
      final resolver = PlayableAudioResolverImpl(storageService: storageService);
      const maliciousSource = CustomAudioSource(
        id: 'custom:exploit',
        displayName: 'Exploit Attempt',
        localRelativePath: 'adhan_sounds/../../etc/passwd',
        originalFileName: 'passwd',
        fileSize: 1024,
      );

      final resolved = await resolver.resolveAudio(maliciousSource, isFajr: false);
      expect(resolved.isFallback, isTrue, reason: 'Resolver must fallback safely on traversal attempt');
      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.fallbackReason, contains('غير آمن'));

      // 3. Path Traversal in AdhanStorageManagerService.deleteAudioFile
      final storageManager = AdhanStorageManagerServiceImpl(
        storageService: storageService,
        prayerConfigDataSource: localDataSource,
        downloadService: FakeAudioDownloadServiceForPhysicalFault(),
        audioStorageLock: audioStorageLock,
        prefs: prefs,
      );

      final deleteResult = await storageManager.deleteAudioFile('adhan_sounds/../../sensitive.txt');
      expect(deleteResult.isLeft(), isTrue);
      deleteResult.fold(
        (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
        (_) => fail('Delete must return SecurityFailure on path traversal'),
      );

      // 4. Physical Linux Symlink Traversal Attack on Android Sandbox
      // Place sensitive target file in parent directory (outside adhan_sounds)
      final sensitiveFile = File(p.join(tempRoot.path, 'system_secret.txt'));
      await sensitiveFile.writeAsString('CONFIDENTIAL_APP_SECRET_TOKEN');

      final symlinkPath = p.join(storageDir.path, 'symlink_exploit.mp3');
      final link = Link(symlinkPath);

      // On Android (Linux kernel), creating symlinks inside the application sandbox is fully supported
      link.createSync(sensitiveFile.path);

      try {
        expect(link.existsSync(), isTrue, reason: 'Physical symlink must be successfully created on Android');

        // Attempt to validate path containment on symlink targeting outside storageDir
        expect(
          () => storageService.validatePathContainment('adhan_sounds/symlink_exploit.mp3'),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              contains('الرابط الرمزي لملف الأذان يشير إلى مسار خارج مجلد الأصوات'),
            ),
          ),
          reason: 'validatePathContainment must detect symlink pointing outside adhan_sounds',
        );

        // Verify inspectStorage handles the symlink safely without traversal
        final inventory = await storageManager.inspectStorage();
        final leak = inventory.files.where((f) => f.fileName == 'system_secret.txt');
        expect(leak.isEmpty, isTrue, reason: 'Symlink target must not leak into storage inventory');

        // Verify sensitive file outside storage remains 100% intact
        expect(await sensitiveFile.exists(), isTrue);
        expect(await sensitiveFile.readAsString(), equals('CONFIDENTIAL_APP_SECRET_TOKEN'));
      } finally {
        if (link.existsSync()) {
          link.deleteSync();
        }
      }
    });
  });
}
