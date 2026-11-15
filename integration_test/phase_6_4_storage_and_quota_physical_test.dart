import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
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
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_state.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/adhan_catalog_screen.dart';

class FakePrayerAlarmConfigLocalDataSource implements BasePrayerAlarmConfigLocalDataSource {
  final Map<PrayerId, PrayerAlarmConfigModel> configs = {};

  @override
  Future<Map<PrayerId, PrayerAlarmConfigModel>> getConfigs() async => configs;

  @override
  Future<PrayerAlarmConfigModel> getConfig(PrayerId prayerId) async =>
      configs[prayerId] ??
      PrayerAlarmConfigModel(
        prayerId: prayerId,
        alarmType: PrayerAlarmType.alarm,
        audioSource: AudioSourceConfig.defaultBuiltInFallback(isFajr: prayerId == PrayerId.fajr),
      );

  @override
  Future<int> getVersion() async => 2;

  @override
  Future<bool> migrateLegacyIfNeeded() async => false;

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfigModel> newConfigs) async {
    configs.addAll(newConfigs);
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfigModel config) async {
    configs[config.prayerId] = config;
  }
}

class FakeAudioDownloadService implements BaseAudioDownloadService {
  final Map<String, AudioDownloadTask> tasks = {};
  final Map<String, StreamController<AudioDownloadTask>> controllers = {};
  final List<String> activeTempPrefixes = [];

  StreamController<AudioDownloadTask> _getController(String entryId) {
    return controllers.putIfAbsent(entryId, () => StreamController<AudioDownloadTask>.broadcast());
  }

  void emitTask(AudioDownloadTask task) {
    tasks[task.entryId] = task;
    _getController(task.entryId).add(task);
  }

  @override
  AudioDownloadTask? getTask(String entryId) => tasks[entryId];

  @override
  List<AudioDownloadTask> getActiveTasks() =>
      tasks.values.where((t) => t.status.isActive).toList();

  @override
  Set<String> getActiveTempPrefixes() => activeTempPrefixes.toSet();

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
  Future<void> cancelDownload(String entryId) async {
    final task = tasks[entryId];
    if (task != null) {
      final cancelled = AudioDownloadTask.cancelled(entryId);
      emitTask(cancelled);
    }
  }

  @override
  Future<void> dispose() async {
    for (final c in controllers.values) {
      await c.close();
    }
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

class FakePlayableAudioResolver implements BasePlayableAudioResolver {
  @override
  Future<ResolvedPlayableAudio> resolveAudio(AudioSourceConfig source, {required bool isFajr}) async {
    return const ResolvedPlayableAudio(path: 'assets/audio/adhan.mp3', isAsset: true);
  }

  @override
  Future<CatalogEntryResolution> resolveCatalogEntry(AdhanCatalogEntry entry) async {
    return const CatalogEntryResolution(
      status: AudioPlayableStatus.requiresDownload,
      localSource: null,
      physicalPath: null,
    );
  }

  @override
  Future<CustomAudioSource?> resolveLocalCustomSource(AdhanCatalogEntry entry) async => null;

  @override
  Future<bool> isAudioPlayableLocally(AudioSourceConfig source) async => true;
}

class FakeStorageManagerServiceForUI implements BaseAdhanStorageManagerService {
  AdhanStorageInventory inventory;
  FakeStorageManagerServiceForUI(this.inventory);

  @override
  Future<AdhanStorageInventory> inspectStorage({Duration ageThreshold = const Duration(minutes: 60)}) async => inventory;

  @override
  Future<Set<String>> getActiveAlarmAudioPaths() async => inventory.activeAlarmPaths;

  @override
  Future<QuotaCheckResult> checkQuota({required int requiredBytes}) async =>
      QuotaCheckResult(
        isAllowed: true,
        requiredBytes: requiredBytes,
        availableQuotaBytes: inventory.availableRemoteQuotaBytes,
        currentUsageBytes: inventory.effectiveRemoteUsageBytes,
        quotaLimitBytes: inventory.remoteCacheQuotaBytes,
        deficitBytes: 0,
      );

  @override
  Future<List<StorageAudioFile>> getAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async =>
      inventory.abandonedTmpFiles;

  @override
  Future<List<StorageAudioFile>> getSafeEvictionCandidates() async => inventory.evictionCandidates;

  @override
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(String relativePath, {bool isUserExplicit = false}) async {
    return const Right(null);
  }

  @override
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async {
    return const StorageCleanupSummary(deletedCount: 0, freedBytes: 0, deletedFileNames: []);
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempBaseDir;
  late CustomAudioStorageService storageService;
  late SharedPreferences prefs;
  late FakePrayerAlarmConfigLocalDataSource configDataSource;
  late FakeAudioDownloadService downloadService;
  late AudioStorageLock storageLock;
  late AdhanStorageManagerServiceImpl storageManager;

  setUp(() async {
    HttpOverrides.global = null;
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

    tempBaseDir = await Directory.systemTemp.createTemp('storage_quota_e2e_');
    storageService = CustomAudioStorageService(docsDirProvider: () async => tempBaseDir);
    await storageService.getStorageDirectory(); // creates adhan_sounds

    configDataSource = FakePrayerAlarmConfigLocalDataSource();
    downloadService = FakeAudioDownloadService();
    storageLock = AudioStorageLock();

    storageManager = AdhanStorageManagerServiceImpl(
      storageService: storageService,
      prayerConfigDataSource: configDataSource,
      downloadService: downloadService,
      audioStorageLock: storageLock,
      prefs: prefs,
      quotaLimitBytes: 150 * 1024 * 1024, // 150 MiB
    );
  });

  tearDown(() async {
    await downloadService.dispose();
    if (await tempBaseDir.exists()) {
      await tempBaseDir.delete(recursive: true);
    }
  });

  group('Phase 6.4 — Storage & Quota Physical Verification', () {
    test('E2E-16 [Quota Admission & Reservation Lifecycle]: Headroom check, in-flight reservation, and atomic release', () async {
      final storageDir = await storageService.getStorageDirectory();

      // 1. Create 140 MiB of existing remote cache files (headroom remaining: 10 MiB)
      final existingFile = File(p.join(storageDir.path, 'remote_old_1122334455667788.mp3'));
      await existingFile.writeAsBytes(List<int>.filled(140 * 1024 * 1024, 0xAA));

      // 2. Admission Check within headroom: 5 MiB -> Allowed
      final checkAllowed = await storageManager.checkQuota(requiredBytes: 5 * 1024 * 1024);
      expect(checkAllowed.isAllowed, isTrue);
      expect(checkAllowed.deficitBytes, equals(0));

      // 3. Admission Check exceeding headroom: 15 MiB (140 + 15 = 155 > 150) -> Rejected
      final checkRejected = await storageManager.checkQuota(requiredBytes: 15 * 1024 * 1024);
      expect(checkRejected.isAllowed, isFalse);
      expect(checkRejected.deficitBytes, equals(5 * 1024 * 1024));

      // 4. In-Flight Reservation: simulate active 8 MiB download
      downloadService.emitTask(AudioDownloadTask(
        entryId: 'remote:active_dl',
        status: DownloadStatus.downloading,
        progress: DownloadProgress.determinate(
          receivedBytes: 2 * 1024 * 1024,
          totalBytes: 8 * 1024 * 1024,
        ),
      ));

      final inventoryWithReservation = await storageManager.inspectStorage();
      expect(inventoryWithReservation.remoteCacheBytes, equals(140 * 1024 * 1024));
      expect(inventoryWithReservation.reservedInFlightBytes, equals(8 * 1024 * 1024));
      expect(inventoryWithReservation.effectiveRemoteUsageBytes, equals(148 * 1024 * 1024));
      expect(inventoryWithReservation.availableRemoteQuotaBytes, equals(2 * 1024 * 1024));

      // 5. Concurrent admission with active reservation: attempt 5 MiB -> Rejected because 148 + 5 = 153 > 150
      final checkConcurrent = await storageManager.checkQuota(requiredBytes: 5 * 1024 * 1024);
      expect(checkConcurrent.isAllowed, isFalse);

      // 6. Reservation Release on Failure / Terminal: task terminates -> reservation drops to 0
      downloadService.emitTask(AudioDownloadTask.failed(
        entryId: 'remote:active_dl',
        failure: AudioDownloadNetworkFailure(),
      ));

      final inventoryAfterFailure = await storageManager.inspectStorage();
      expect(inventoryAfterFailure.reservedInFlightBytes, equals(0));
      expect(inventoryAfterFailure.effectiveRemoteUsageBytes, equals(140 * 1024 * 1024));
      expect(inventoryAfterFailure.availableRemoteQuotaBytes, equals(10 * 1024 * 1024));
    });

    test('E2E-17 [Storage Inventory Accuracy]: Accurate accounting across all categories & custom exemption', () async {
      final storageDir = await storageService.getStorageDirectory();
      final tmpDir = Directory(p.join(storageDir.path, '.tmp'));
      await tmpDir.create(recursive: true);

      // Create files across all classifications
      // 1. Remote cache file (5 MiB)
      final remoteFile = File(p.join(storageDir.path, 'remote_qari_1122334455667788.mp3'));
      await remoteFile.writeAsBytes(List<int>.filled(5 * 1024 * 1024, 0x11));

      // 2. User custom file (3 MiB)
      final customFile = File(p.join(storageDir.path, 'custom_12345.mp3'));
      await customFile.writeAsBytes(List<int>.filled(3 * 1024 * 1024, 0x22));

      // 3. Staging file in .tmp (1 MiB)
      final stagingFile = File(p.join(tmpDir.path, 'dl_99_1000.tmp'));
      await stagingFile.writeAsBytes(List<int>.filled(1 * 1024 * 1024, 0x33));

      // 4. Unmanaged file (2 KiB)
      final unmanagedFile = File(p.join(storageDir.path, 'notes.txt'));
      await unmanagedFile.writeAsBytes(List<int>.filled(2048, 0x44));

      final inventory = await storageManager.inspectStorage();

      expect(inventory.remoteCacheBytes, equals(5 * 1024 * 1024));
      expect(inventory.userCustomBytes, equals(3 * 1024 * 1024));
      expect(inventory.stagingTmpBytes, equals(1 * 1024 * 1024));
      expect(inventory.unmanagedBytes, equals(2048));
      expect(inventory.totalDirectoryBytes, equals((5 + 3 + 1) * 1024 * 1024 + 2048));

      // Strictly verify effective remote usage only accounts for remote cache
      expect(inventory.effectiveRemoteUsageBytes, equals(5 * 1024 * 1024));
    });

    test('E2E-18 [Protected Audio Verification]: Active prayer & global alarm audio is strictly protected', () async {
      final storageDir = await storageService.getStorageDirectory();

      // Remote cache file assigned to Fajr
      final fajrFile = File(p.join(storageDir.path, 'remote_fajr_1122334455667788.mp3'));
      await fajrFile.writeAsBytes(List<int>.filled(1024, 0x01));

      // Remote cache file assigned as Global Default
      final globalFile = File(p.join(storageDir.path, 'remote_global_2233445566778899.mp3'));
      await globalFile.writeAsBytes(List<int>.filled(1024, 0x02));

      // Configure Fajr alarm in dataSource
      await configDataSource.saveConfig(PrayerAlarmConfigModel(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: CustomAudioSource(
          id: 'custom:remote_fajr',
          displayName: 'أذان الفجر',
          localRelativePath: 'adhan_sounds/remote_fajr_1122334455667788.mp3',
          originalFileName: 'fajr.mp3',
          fileSize: 1024,
        ),
      ));

      // Configure Global Default in SharedPreferences
      await prefs.setString(
        'global_adhan_audio_source',
        jsonEncode({
          'type': 'custom',
          'id': 'custom:remote_global',
          'displayName': 'الأذان العام',
          'localRelativePath': 'adhan_sounds/remote_global_2233445566778899.mp3',
          'originalFileName': 'global.mp3',
          'fileSize': 1024,
        }),
      );

      // Attempt to delete Fajr audio
      final fajrDeleteResult = await storageManager.deleteAudioFile('adhan_sounds/remote_fajr_1122334455667788.mp3');
      expect(fajrDeleteResult.isLeft(), isTrue);
      fajrDeleteResult.fold(
        (failure) {
          expect(failure, isA<StorageDeletionActiveAlarmFailure>());
          expect((failure as StorageDeletionActiveAlarmFailure).prayerNames, contains('الفجر'));
        },
        (_) => fail('Fajr audio deletion must fail'),
      );
      expect(await fajrFile.exists(), isTrue);

      // Attempt to delete Global Default audio
      final globalDeleteResult = await storageManager.deleteAudioFile('adhan_sounds/remote_global_2233445566778899.mp3');
      expect(globalDeleteResult.isLeft(), isTrue);
      globalDeleteResult.fold(
        (failure) {
          expect(failure, isA<StorageDeletionActiveAlarmFailure>());
          expect((failure as StorageDeletionActiveAlarmFailure).prayerNames, contains('الافتراضي العام للصلوات'));
        },
        (_) => fail('Global audio deletion must fail'),
      );
      expect(await globalFile.exists(), isTrue);
    });

    test('E2E-19 [Safe Eviction & JIT Revalidation]: Unassigned file evicted safely; live assignment under lock aborts eviction', () async {
      final storageDir = await storageService.getStorageDirectory();

      final evictableFile = File(p.join(storageDir.path, 'remote_evict_3344556677889900.mp3'));
      await evictableFile.writeAsBytes(List<int>.filled(2048, 0x55));

      final inventory = await storageManager.inspectStorage();
      expect(inventory.evictionCandidates.length, equals(1));
      expect(inventory.evictionCandidates.first.fileName, equals('remote_evict_3344556677889900.mp3'));

      // 1. Successful Safe Eviction
      final deleteResult = await storageManager.deleteAudioFile('adhan_sounds/remote_evict_3344556677889900.mp3');
      expect(deleteResult.isRight(), isTrue);
      expect(await evictableFile.exists(), isFalse);

      final updatedInventory = await storageManager.inspectStorage();
      expect(updatedInventory.evictionCandidates, isEmpty);
      expect(updatedInventory.remoteCacheBytes, equals(0));

      // 2. Just-In-Time Race Revalidation: recreate file, pretend inspectStorage deemed it evictable, but user assigned it before lock
      final raceFile = File(p.join(storageDir.path, 'remote_race_4455667788990011.mp3'));
      await raceFile.writeAsBytes(List<int>.filled(2048, 0x66));

      // User assigns it to Dhuhr before deletion executes
      await configDataSource.saveConfig(PrayerAlarmConfigModel(
        prayerId: PrayerId.dhuhr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: CustomAudioSource(
          id: 'custom:remote_race',
          displayName: 'أذان الظهر',
          localRelativePath: 'adhan_sounds/remote_race_4455667788990011.mp3',
          originalFileName: 'race.mp3',
          fileSize: 2048,
        ),
      ));

      // Deletion is rejected under lock!
      final raceDeleteResult = await storageManager.deleteAudioFile('adhan_sounds/remote_race_4455667788990011.mp3');
      expect(raceDeleteResult.isLeft(), isTrue);
      expect(raceDeleteResult.swap().toOption().toNullable(), isA<StorageDeletionActiveAlarmFailure>());
      expect(await raceFile.exists(), isTrue);
    });

    test('E2E-20 [Quota Boundary Verification]: Exact ratio transitions for normal, warning, and full states', () async {
      const quota = 100 * 1024 * 1024; // 100 MiB

      AdhanStorageInventory makeInventory({required int remoteBytes, int reservedBytes = 0}) {
        return AdhanStorageInventory(
          totalDirectoryBytes: remoteBytes + reservedBytes,
          remoteCacheBytes: remoteBytes,
          userCustomBytes: 0,
          stagingTmpBytes: 0,
          unmanagedBytes: 0,
          reservedInFlightBytes: reservedBytes,
          remoteCacheQuotaBytes: quota,
          files: const [],
          activeAlarmPaths: const {},
          abandonedTmpFiles: const [],
          evictionCandidates: const [],
        );
      }

      // 0%
      final state0 = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: 0),
      );
      expect(state0.quotaUsageRatio, equals(0.0));
      expect(state0.isQuotaWarning, isFalse);
      expect(state0.isQuotaExceeded, isFalse);

      // 84.9%
      final state84 = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: (84.9 * 1024 * 1024).floor()),
      );
      expect(state84.quotaUsageRatio, lessThan(0.85));
      expect(state84.isQuotaWarning, isFalse);

      // 85.0% (Warning condition triggered)
      final state85 = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: (85.0 * 1024 * 1024).floor()),
      );
      expect(state85.quotaUsageRatio, greaterThanOrEqualTo(0.85));
      expect(state85.isQuotaWarning, isTrue);
      expect(state85.isQuotaExceeded, isFalse);

      // 100.0% (Full condition triggered)
      final state100 = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: quota),
      );
      expect(state100.quotaUsageRatio, equals(1.0));
      expect(state100.isQuotaWarning, isFalse);
      expect(state100.isQuotaExceeded, isTrue);

      // In-flight reservation crossing into warning: 80 MiB remoteCache + 6 MiB reserved = 86 MiB (86%)
      final stateResWarning = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: 80 * 1024 * 1024, reservedBytes: 6 * 1024 * 1024),
      );
      expect(stateResWarning.quotaUsageRatio, equals(0.86));
      expect(stateResWarning.isQuotaWarning, isTrue);

      // In-flight reservation crossing into full: 95 MiB remoteCache + 5 MiB reserved = 100 MiB (100%)
      final stateResFull = AdhanCatalogState(
        storageStatus: StorageStatus.loaded,
        storageInventory: makeInventory(remoteBytes: 95 * 1024 * 1024, reservedBytes: 5 * 1024 * 1024),
      );
      expect(stateResFull.quotaUsageRatio, equals(1.0));
      expect(stateResFull.isQuotaExceeded, isTrue);
    });

    test('E2E-21 [User Custom Audio Exemption]: Custom audio exempt from remote quota & deletion protection', () async {
      final storageDir = await storageService.getStorageDirectory();

      // Create a 50 MiB user custom sound
      final customFile = File(p.join(storageDir.path, 'custom_9999.mp3'));
      await customFile.writeAsBytes(List<int>.filled(50 * 1024 * 1024, 0x77));

      final inventory = await storageManager.inspectStorage();
      expect(inventory.userCustomBytes, equals(50 * 1024 * 1024));
      expect(inventory.remoteCacheBytes, equals(0));
      expect(inventory.effectiveRemoteUsageBytes, equals(0));
      expect(inventory.evictionCandidates, isEmpty);

      // Implicit deletion rejected
      final implicitDelete = await storageManager.deleteAudioFile(
        'adhan_sounds/custom_9999.mp3',
        isUserExplicit: false,
      );
      expect(implicitDelete.isLeft(), isTrue);
      expect(implicitDelete.swap().toOption().toNullable(), isA<StorageDeletionProtectedFailure>());
      expect(await customFile.exists(), isTrue);

      // Explicit user deletion allowed
      final explicitDelete = await storageManager.deleteAudioFile(
        'adhan_sounds/custom_9999.mp3',
        isUserExplicit: true,
      );
      expect(explicitDelete.isRight(), isTrue);
      expect(await customFile.exists(), isFalse);
    });

    test('E2E-22 [Failure & Recovery]: Missing file and directory deletion recovery', () async {
      // 1. Delete non-existent file
      final notFoundResult = await storageManager.deleteAudioFile('adhan_sounds/remote_nonexistent_1122334455667788.mp3');
      expect(notFoundResult.isLeft(), isTrue);
      expect(notFoundResult.swap().toOption().toNullable(), isA<StorageDeletionNotFoundFailure>());

      // 2. Directory missing -> inspect returns empty inventory
      final storageDir = await storageService.getStorageDirectory();
      await storageDir.delete(recursive: true);

      final emptyInventory = await storageManager.inspectStorage();
      expect(emptyInventory.totalDirectoryBytes, equals(0));
      expect(emptyInventory.remoteCacheBytes, equals(0));

      // 3. Re-create directory and recover
      await storageService.getStorageDirectory();
      final recoveredInventory = await storageManager.inspectStorage();
      expect(recoveredInventory.totalDirectoryBytes, equals(0));
    });

    testWidgets('E2E-23 [Storage UI Physical Verification]: Banner transitions, modal details, and safe eviction', (WidgetTester tester) async {
      final catalogEntry = AdhanCatalogEntry(
        id: 'remote:entry_ui_1',
        sheikhName: 'الشيخ عبد الباسط',
        audioType: AdhanAudioType.general,
        displayName: 'أذان الحرم المكي',
        durationSeconds: 180,
        objectKey: 'audio/makkah.mp3',
        fileSizeBytes: 10 * 1024 * 1024,
        sha256: 'a' * 64,
      );

      final catalog = AdhanCatalog(
        schemaVersion: 1,
        generatedAt: DateTime.now().toIso8601String(),
        entries: [catalogEntry],
      );

      final catalogRepo = FakeCatalogRepository()..catalog = catalog;
      final playableResolver = FakePlayableAudioResolver();

      final uiStorageManager = FakeStorageManagerServiceForUI(
        const AdhanStorageInventory(
          totalDirectoryBytes: 10 * 1024 * 1024,
          remoteCacheBytes: 10 * 1024 * 1024,
          userCustomBytes: 0,
          stagingTmpBytes: 0,
          unmanagedBytes: 0,
          reservedInFlightBytes: 0,
          remoteCacheQuotaBytes: 150 * 1024 * 1024,
          files: [],
          activeAlarmPaths: {},
          abandonedTmpFiles: [],
          evictionCandidates: [],
        ),
      );

      // Create a test cubit
      final cubit = AdhanCatalogCubit(
        catalogRepository: catalogRepo,
        downloadService: downloadService,
        playableAudioResolver: playableResolver,
        storageManagerService: uiStorageManager,
        audioPlayer: FakeAudioPlayer(),
      );

      if (sl.isRegistered<AdhanCatalogCubit>()) {
        sl.unregister<AdhanCatalogCubit>();
      }
      sl.registerFactory<AdhanCatalogCubit>(() => cubit);

      // Helper to build screen
      Widget buildTestApp() {
        return const MaterialApp(
          home: Scaffold(
            body: AdhanCatalogScreen(
              currentSelectedSource: AudioSourceConfig.defaultMishary,
            ),
          ),
        );
      }

      // 1. Normal state (<85%): Normal banner with 'تفاصيل الذاكرة'
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('تفاصيل الذاكرة'), findsOneWidget);

      // 2. Warning state (>= 85%): Emit inventory at 88%
      const warningInventory = AdhanStorageInventory(
        totalDirectoryBytes: 132 * 1024 * 1024,
        remoteCacheBytes: 132 * 1024 * 1024, // 132/150 = 88%
        userCustomBytes: 0,
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: [],
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
      );
      uiStorageManager.inventory = warningInventory;
      cubit.emit(cubit.state.copyWith(
        storageStatus: StorageStatus.loaded,
        storageInventory: warningInventory,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('تحذير: اقتراب امتلاء كاش الأصوات'), findsOneWidget);
      expect(find.text('تفاصيل الذاكرة'), findsOneWidget);

      // 3. Full state (100%): Emit inventory at 100%
      const fullInventory = AdhanStorageInventory(
        totalDirectoryBytes: 150 * 1024 * 1024,
        remoteCacheBytes: 150 * 1024 * 1024,
        userCustomBytes: 0,
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: [],
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
      );
      uiStorageManager.inventory = fullInventory;
      cubit.emit(cubit.state.copyWith(
        storageStatus: StorageStatus.loaded,
        storageInventory: fullInventory,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('تم بلوغ الحد الأقصى لكاش الأصوات'), findsOneWidget);

      // 4. Open Storage Details Bottom Sheet
      await tester.tap(find.text('تفاصيل الذاكرة'));
      await tester.pumpAndSettle();

      // Verify Modal Content
      expect(find.textContaining('كاش الأصوات السحابية'), findsWidgets);
      expect(find.text('إغلاق'), findsOneWidget);

      // Close modal
      await tester.ensureVisible(find.text('إغلاق'));
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
      expect(find.text('إغلاق'), findsNothing);
    });
  });
}

