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
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/playable_audio_resolver_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';

class BlockingNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('Blocked: Airplane mode simulation (Zero network allowed)');
  }
}

class FakeAudioPlayer extends AudioPlayer {
  FakeAudioPlayer() : super(playerId: 'fake_player_id');
  bool isPlaying = false;
  Source? currentSource;

  @override
  Future<void> play(Source source, {double? volume, double? balance, AudioContext? ctx, Duration? position, PlayerMode? mode}) async {
    isPlaying = true;
    currentSource = source;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    isPlaying = false;
  }
}

class FakeCatalogRepository implements BaseAdhanCatalogRepository {
  AdhanCatalog? catalog;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    if (catalog != null) return Right(catalog!);
    return Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    if (catalog != null) return Right(catalog!);
    return Left(CatalogNetworkFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class FakeAudioDownloadService implements BaseAudioDownloadService {
  final Map<String, AudioDownloadTask> tasks = {};
  final Map<String, StreamController<AudioDownloadTask>> controllers = {};

  StreamController<AudioDownloadTask> _getController(String entryId) {
    return controllers.putIfAbsent(entryId, () => StreamController<AudioDownloadTask>.broadcast());
  }

  @override
  AudioDownloadTask? getTask(String entryId) => tasks[entryId];

  @override
  List<AudioDownloadTask> getActiveTasks() =>
      tasks.values.where((t) => t.status.isActive).toList();

  @override
  Set<String> getActiveTempPrefixes() => const {};

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) => _getController(entryId).stream;

  @override
  Future<bool> isAudioDownloaded(String entryId) async => false;

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(
    AdhanCatalogEntry entry, {
    void Function(DownloadProgress p1)? onProgress,
  }) async {
    return Left(AudioDownloadNetworkFailure());
  }

  @override
  Future<void> cancelDownload(String entryId) async {}

  @override
  Future<void> dispose() async {
    for (final c in controllers.values) {
      await c.close();
    }
  }
}

class FakeStorageManagerService implements BaseAdhanStorageManagerService {
  @override
  Future<AdhanStorageInventory> inspectStorage({Duration ageThreshold = const Duration(minutes: 60)}) async =>
      AdhanStorageInventory.empty();

  @override
  Future<Set<String>> getActiveAlarmAudioPaths() async => const {};

  @override
  Future<QuotaCheckResult> checkQuota({required int requiredBytes}) async =>
      const QuotaCheckResult(
        isAllowed: true,
        requiredBytes: 0,
        availableQuotaBytes: 150 * 1024 * 1024,
        currentUsageBytes: 0,
        quotaLimitBytes: 150 * 1024 * 1024,
        deficitBytes: 0,
      );

  @override
  Future<List<StorageAudioFile>> getAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async =>
      const [];

  @override
  Future<List<StorageAudioFile>> getSafeEvictionCandidates() async => const [];

  @override
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(String relativePath, {bool isUserExplicit = false}) async =>
      const Right(null);

  @override
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async =>
      const StorageCleanupSummary(deletedCount: 0, freedBytes: 0, deletedFileNames: []);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempBaseDir;
  late CustomAudioStorageService storageService;
  late SharedPreferences prefs;
  late PlayableAudioResolverImpl resolver;
  late FakeAudioPlayer audioPlayer;
  late FakeCatalogRepository catalogRepo;
  late FakeAudioDownloadService downloadService;
  late FakeStorageManagerService storageManager;

  final sampleEntry = AdhanCatalogEntry(
    id: 'remote:abdulbasit_fajr',
    sheikhName: 'الشيخ عبد الباسط عبد الصمد',
    audioType: AdhanAudioType.fajr,
    displayName: 'أذان الفجر النادر',
    durationSeconds: 195,
    objectKey: 'audio/abdulbasit.mp3',
    fileSizeBytes: 2 * 1024 * 1024,
    sha256: 'b' * 64,
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers/events/fake_player_id'),
      (MethodCall methodCall) async => null,
    );

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    tempBaseDir = await Directory.systemTemp.createTemp('playback_alarm_physical_');
    storageService = CustomAudioStorageService(docsDirProvider: () async => tempBaseDir);
    await storageService.getStorageDirectory(); // creates adhan_sounds

    resolver = PlayableAudioResolverImpl(storageService: storageService);
    audioPlayer = FakeAudioPlayer();
    catalogRepo = FakeCatalogRepository();
    downloadService = FakeAudioDownloadService();
    storageManager = FakeStorageManagerService();
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await downloadService.dispose();
    await audioPlayer.dispose();
    if (await tempBaseDir.exists()) {
      await tempBaseDir.delete(recursive: true);
    }
  });

  group('Phase 6.5 — Playback & Alarm Engine Regression', () {
    test('E2E-24 [Offline Audio Preview]: Preview plays exclusively from device storage via DeviceFileSource', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));

      // Physically create the downloaded audio file
      await physicalFile.writeAsBytes(List<int>.filled(1024, 0x12));

      // Enforce strict Airplane mode (all network sockets throw immediately)
      HttpOverrides.global = BlockingNetworkHttpOverrides();

      final cubit = AdhanCatalogCubit(
        catalogRepository: catalogRepo,
        downloadService: downloadService,
        playableAudioResolver: resolver,
        storageManagerService: storageManager,
        audioPlayer: audioPlayer,
      );

      // Play remote entry preview offline
      await cubit.playRemoteEntryPreview(sampleEntry);

      expect(cubit.state.isPreviewPlaying, isTrue);
      expect(cubit.state.playingAudioId, equals(sampleEntry.id));
      expect(audioPlayer.isPlaying, isTrue);

      // Verify it played via DeviceFileSource pointing to physical filesystem path
      expect(audioPlayer.currentSource, isA<DeviceFileSource>());
      final deviceSource = audioPlayer.currentSource as DeviceFileSource;
      expect(deviceSource.path, equals(physicalFile.path));

      // Stop preview
      await cubit.stopPreview();
      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(audioPlayer.isPlaying, isFalse);
      await cubit.close();
    });

    test('E2E-25 [Zero Remote Streaming]: Un-downloaded entry preview strictly refuses remote streaming', () async {
      // Ensure file does NOT exist locally
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      if (await physicalFile.exists()) {
        await physicalFile.delete();
      }

      final cubit = AdhanCatalogCubit(
        catalogRepository: catalogRepo,
        downloadService: downloadService,
        playableAudioResolver: resolver,
        storageManagerService: storageManager,
        audioPlayer: audioPlayer,
      );

      // Attempt to preview un-downloaded sound
      await cubit.playRemoteEntryPreview(sampleEntry);

      // Verify preview was refused, no playback was started, and warning notice was emitted
      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(audioPlayer.isPlaying, isFalse);
      expect(audioPlayer.currentSource, isNull);
      expect(cubit.state.userNotice, equals('يجب تنزيل الأذان أولاً للاستماع إليه'));

      await cubit.close();
    });

    test('E2E-26 [Prayer Alarm Full Cycle]: User assigns downloaded remote audio to Fajr; resolves cleanly for scheduling', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      await physicalFile.writeAsBytes(List<int>.filled(2048, 0x34));

      final configDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final configRepo = PrayerAlarmConfigRepositoryImpl(
        localDataSource: configDataSource,
        storageService: storageService,
        audioStorageLock: AudioStorageLock(),
      );

      // 1. Resolve local CustomAudioSource from catalog entry
      final customSource = await resolver.resolveLocalCustomSource(sampleEntry);
      expect(customSource, isNotNull);
      expect(customSource!.id, equals('custom:${sampleEntry.id}'));

      // 2. Assign custom audio source to Fajr prayer alarm config
      final fajrConfig = PrayerAlarmConfigModel(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      );
      await configRepo.saveConfig(fajrConfig);

      // 3. Resolve audio for alarm scheduler dispatch
      final resolved = await resolver.resolveAudio(customSource, isFajr: true);
      expect(resolved.isAsset, isFalse);
      expect(resolved.isFallback, isFalse);
      expect(resolved.path, equals(physicalFile.path));

      // 4. Verify stored configuration in repo remained intact
      final storedConfig = await configRepo.getConfig(PrayerId.fajr);
      expect(storedConfig.audioSource, equals(customSource));
    });

    test('E2E-27 [Missing File Safe Fallback]: Out-of-band deleted remote audio falls back to Mishary with 0 network calls and untouched config', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      await physicalFile.writeAsBytes(List<int>.filled(2048, 0x56));

      final configDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final configRepo = PrayerAlarmConfigRepositoryImpl(
        localDataSource: configDataSource,
        storageService: storageService,
        audioStorageLock: AudioStorageLock(),
      );

      final customSource = CustomAudioSource(
        id: 'custom:${sampleEntry.id}',
        displayName: sampleEntry.displayName,
        localRelativePath: p.join('adhan_sounds', targetFileName),
        originalFileName: p.basename(sampleEntry.objectKey),
        fileSize: 2048,
      );

      await configRepo.saveConfig(PrayerAlarmConfigModel(
        prayerId: PrayerId.dhuhr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      ));

      // Simulate out-of-band file deletion (e.g. storage cleaner or file manager)
      await physicalFile.delete();
      expect(await physicalFile.exists(), isFalse);

      // Enforce strict airplane mode: 0 network calls allowed
      HttpOverrides.global = BlockingNetworkHttpOverrides();

      // Resolve audio for Dhuhr alarm
      final resolved = await resolver.resolveAudio(customSource, isFajr: false);

      // Safe Fallback Assertions:
      // 1. Safe fallback triggered
      expect(resolved.isFallback, isTrue);
      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.fallbackReason, contains('غير موجود'));

      // 2. Stored configuration in preferences is NEVER destroyed or altered
      final storedConfig = await configRepo.getConfig(PrayerId.dhuhr);
      expect(storedConfig.audioSource, isA<CustomAudioSource>());
      expect((storedConfig.audioSource as CustomAudioSource).id, equals(customSource.id));
    });

    test('E2E-28 [Reboot Persistence & Offline Resolution]: Persisted custom audio resolves offline after restart', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      await physicalFile.writeAsBytes(List<int>.filled(4096, 0x78));

      final customSource = CustomAudioSource(
        id: 'custom:${sampleEntry.id}',
        displayName: sampleEntry.displayName,
        localRelativePath: p.join('adhan_sounds', targetFileName),
        originalFileName: p.basename(sampleEntry.objectKey),
        fileSize: 4096,
      );

      // Save config in SharedPreferences
      final configDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      await configDataSource.saveConfig(PrayerAlarmConfigModel(
        prayerId: PrayerId.asr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      ));

      // Simulate device reboot / app restart: create brand-new instances from persisted prefs
      HttpOverrides.global = BlockingNetworkHttpOverrides(); // Airplane mode after reboot

      final freshStorageService = CustomAudioStorageService(docsDirProvider: () async => tempBaseDir);
      final freshResolver = PlayableAudioResolverImpl(storageService: freshStorageService);
      final freshDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final freshRepo = PrayerAlarmConfigRepositoryImpl(
        localDataSource: freshDataSource,
        storageService: freshStorageService,
        audioStorageLock: AudioStorageLock(),
      );

      // Verify stored config after restart
      final asrConfig = await freshRepo.getConfig(PrayerId.asr);
      expect(asrConfig.audioSource, equals(customSource));

      // Verify local playability check passes without network
      final isPlayable = await freshResolver.isAudioPlayableLocally(asrConfig.audioSource);
      expect(isPlayable, isTrue);

      // Verify alarm resolution resolves directly to disk file without fallback
      final resolved = await freshResolver.resolveAudio(asrConfig.audioSource, isFajr: false);
      expect(resolved.isFallback, isFalse);
      expect(resolved.isAsset, isFalse);
      expect(resolved.path, equals(physicalFile.path));
    });
  });
}

