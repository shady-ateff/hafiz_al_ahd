import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_state.dart';

class FakeAdhanCatalogRepository implements BaseAdhanCatalogRepository {
  Either<AdhanCatalogFailure, AdhanCatalog>? getCatalogResult;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    return getCatalogResult ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    return getCatalogResult ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class FakeAudioDownloadService implements BaseAudioDownloadService {
  final Map<String, StreamController<AudioDownloadTask>> controllers = {};
  final Map<String, AudioDownloadTask> tasks = {};
  Either<AudioDownloadFailure, CustomAudioSource>? downloadResult;
  String? lastCancelledEntryId;

  StreamController<AudioDownloadTask> _getOrCreateController(String entryId) {
    return controllers.putIfAbsent(entryId, () => StreamController<AudioDownloadTask>.broadcast());
  }

  void emitTask(AudioDownloadTask task) {
    tasks[task.entryId] = task;
    _getOrCreateController(task.entryId).add(task);
  }

  @override
  AudioDownloadTask? getTask(String entryId) => tasks[entryId];

  @override
  List<AudioDownloadTask> getActiveTasks() =>
      tasks.values.where((t) => t.status.isActive).toList();

  @override
  Set<String> getActiveTempPrefixes() => const {};

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) {
    return _getOrCreateController(entryId).stream;
  }

  @override
  Future<bool> isAudioDownloaded(String entryId) async {
    return tasks[entryId]?.status == DownloadStatus.completed;
  }

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(AdhanCatalogEntry entry) async {
    return downloadResult ?? Left(AudioDownloadNetworkFailure());
  }

  @override
  Future<void> cancelDownload(String entryId) async {
    lastCancelledEntryId = entryId;
    emitTask(AudioDownloadTask.cancelled(entryId));
  }

  @override
  Future<void> dispose() async {
    for (final c in controllers.values) {
      await c.close();
    }
    controllers.clear();
  }
}

class FakePlayableAudioResolver implements BasePlayableAudioResolver {
  Map<String, CatalogEntryResolution> catalogResolutions = {};
  Map<String, ResolvedPlayableAudio> audioResolutions = {};

  @override
  Future<CatalogEntryResolution> resolveCatalogEntry(AdhanCatalogEntry entry) async {
    return catalogResolutions[entry.id] ??
        const CatalogEntryResolution(status: AudioPlayableStatus.requiresDownload);
  }

  @override
  Future<CustomAudioSource?> resolveLocalCustomSource(AdhanCatalogEntry entry) async {
    final res = await resolveCatalogEntry(entry);
    return res.localSource;
  }

  @override
  Future<ResolvedPlayableAudio> resolveAudio(AudioSourceConfig source, {required bool isFajr}) async {
    return audioResolutions[source.id] ??
        ResolvedPlayableAudio(
          path: isFajr ? 'assets/sounds/fajr_azan.mp3' : 'assets/sounds/adhan.mp3',
          isAsset: true,
          isFallback: false,
        );
  }

  @override
  Future<bool> isAudioPlayableLocally(AudioSourceConfig source) async => true;
}

class FakeAudioPlayer extends AudioPlayer {
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

class FakeStorageManagerService implements BaseAdhanStorageManagerService {
  AdhanStorageInventory inventory = AdhanStorageInventory.empty();
  Either<StorageDeletionFailure, void>? deleteResult;
  String? lastDeletedPath;
  QuotaCheckResult? customQuotaCheckResult;
  bool throwOnInspect = false;
  Completer<AdhanStorageInventory>? pendingInspectCompleter;
  int inspectCallCount = 0;

  @override
  Future<AdhanStorageInventory> inspectStorage() async {
    inspectCallCount++;
    if (throwOnInspect) {
      throw Exception('Storage disk I/O failure');
    }
    if (pendingInspectCompleter != null) {
      return pendingInspectCompleter!.future;
    }
    return inventory;
  }

  @override
  Future<Set<String>> getActiveAlarmAudioPaths() async => inventory.activeAlarmPaths;

  @override
  Future<QuotaCheckResult> checkQuota({required int requiredBytes}) async {
    if (customQuotaCheckResult != null) return customQuotaCheckResult!;
    final isAllowed = inventory.effectiveRemoteUsageBytes + requiredBytes <= inventory.remoteCacheQuotaBytes;
    final deficit = isAllowed ? 0 : (inventory.effectiveRemoteUsageBytes + requiredBytes) - inventory.remoteCacheQuotaBytes;
    return QuotaCheckResult(
      isAllowed: isAllowed,
      requiredBytes: requiredBytes,
      availableQuotaBytes: inventory.availableRemoteQuotaBytes,
      currentUsageBytes: inventory.effectiveRemoteUsageBytes,
      quotaLimitBytes: inventory.remoteCacheQuotaBytes,
      deficitBytes: deficit,
    );
  }

  @override
  Future<List<StorageAudioFile>> getAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async =>
      inventory.abandonedTmpFiles;

  @override
  Future<List<StorageAudioFile>> getSafeEvictionCandidates() async =>
      inventory.evictionCandidates;

  @override
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(String relativePath, {bool isUserExplicit = false}) async {
    lastDeletedPath = relativePath;
    return deleteResult ?? const Right(null);
  }

  @override
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async {
    return const StorageCleanupSummary(deletedCount: 2, freedBytes: 4096, deletedFileNames: ['dl_1.tmp', 'dl_2.tmp']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdhanCatalogRepository catalogRepo;
  late FakeAudioDownloadService downloadService;
  late FakePlayableAudioResolver resolver;
  late FakeStorageManagerService storageManager;
  late FakeAudioPlayer audioPlayer;
  late AdhanCatalogCubit cubit;

  final sampleEntry = AdhanCatalogEntry(
    id: 'remote:sheikh_test',
    sheikhName: 'الشيخ الاختباري',
    audioType: AdhanAudioType.general,
    displayName: 'أذان تجريبي رائع',
    durationSeconds: 65,
    objectKey: 'audio/test.mp3',
    fileSizeBytes: 1000000,
    sha256: 'a' * 64,
  );

  final sampleCatalog = AdhanCatalog(
    schemaVersion: 1,
    generatedAt: '2026-11-13T12:00:00Z',
    entries: [sampleEntry],
  );

  setUp(() {
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

    catalogRepo = FakeAdhanCatalogRepository();
    downloadService = FakeAudioDownloadService();
    resolver = FakePlayableAudioResolver();
    storageManager = FakeStorageManagerService();
    audioPlayer = FakeAudioPlayer();

    cubit = AdhanCatalogCubit(
      catalogRepository: catalogRepo,
      downloadService: downloadService,
      playableAudioResolver: resolver,
      storageManagerService: storageManager,
      audioPlayer: audioPlayer,
    );
  });

  tearDown(() async {
    await cubit.close();
    await downloadService.dispose();
  });

  group('AdhanCatalogCubit — Catalog Loading', () {
    test('loadCatalog successfully loads entries and resolves statuses', () async {
      catalogRepo.getCatalogResult = Right(sampleCatalog);
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.requiresDownload,
      );

      final future = cubit.loadCatalog();

      expect(cubit.state.status, equals(CatalogStatus.loading));

      await future;

      expect(cubit.state.status, equals(CatalogStatus.loaded));
      expect(cubit.state.catalog, equals(sampleCatalog));
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.requiresDownload));
      expect(cubit.state.localSources[sampleEntry.id], isNull);
    });

    test('loadCatalog populates localSource if already downloaded and ready', () async {
      catalogRepo.getCatalogResult = Right(sampleCatalog);

      const localSource = CustomAudioSource(
        id: 'custom:remote:sheikh_test',
        displayName: 'أذان تجريبي رائع',
        localRelativePath: 'adhan_sounds/remote_sheikh_test_aaa.mp3',
        originalFileName: 'test.mp3',
        fileSize: 1000000,
      );

      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: localSource,
        physicalPath: '/storage/adhan_sounds/remote_sheikh_test_aaa.mp3',
      );

      await cubit.loadCatalog();

      expect(cubit.state.status, equals(CatalogStatus.loaded));
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.ready));
      expect(cubit.state.localSources[sampleEntry.id], equals(localSource));
    });

    test('loadCatalog handles error failure cleanly', () async {
      catalogRepo.getCatalogResult = Left(CatalogNetworkFailure(message: 'خطأ اتصال بالشبكة'));

      await cubit.loadCatalog();

      expect(cubit.state.status, equals(CatalogStatus.error));
      expect(cubit.state.errorMessage, equals('خطأ اتصال بالشبكة'));
      expect(cubit.state.isOffline, isTrue);
    });
  });

  group('AdhanCatalogCubit — Download Lifecycle & State Coordination', () {
    test('startDownload updates progress and resolves to ready on completion', () async {
      catalogRepo.getCatalogResult = Right(sampleCatalog);
      await cubit.loadCatalog();

      const downloadedSource = CustomAudioSource(
        id: 'custom:remote:sheikh_test',
        displayName: 'أذان تجريبي رائع',
        localRelativePath: 'adhan_sounds/remote_sheikh_test_aaa.mp3',
        originalFileName: 'test.mp3',
        fileSize: 1000000,
      );

      downloadService.downloadResult = const Right(downloadedSource);
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: downloadedSource,
        physicalPath: '/storage/adhan_sounds/remote_sheikh_test_aaa.mp3',
      );

      // Start download
      final downloadFuture = cubit.startDownload(sampleEntry);
      await pumpEventQueue();

      // Emit active progress event
      downloadService.emitTask(AudioDownloadTask.downloading(
        entryId: sampleEntry.id,
        progress: DownloadProgress.determinate(receivedBytes: 500000, totalBytes: 1000000),
      ));

      await pumpEventQueue();

      final activeTask = cubit.state.downloadTasks[sampleEntry.id];
      expect(activeTask, isNotNull);
      expect(activeTask!.status, equals(DownloadStatus.downloading));
      expect(activeTask.progress.percentage, equals(50));

      await downloadFuture;

      // Verified ready state
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.ready));
      expect(cubit.state.localSources[sampleEntry.id], equals(downloadedSource));
    });

    test('startDownload emits userNotice on failure', () async {
      catalogRepo.getCatalogResult = Right(sampleCatalog);
      await cubit.loadCatalog();

      downloadService.downloadResult = Left(AudioDownloadIntegrityFailure(actualHash: '1', expectedHash: '2'));

      await cubit.startDownload(sampleEntry);

      expect(cubit.state.userNotice, isNotNull);
      expect(cubit.state.userNotice, contains('SHA-256'));
    });

    test('cancelDownload delegates to downloadService', () async {
      await cubit.cancelDownload(sampleEntry.id);
      expect(downloadService.lastCancelledEntryId, equals(sampleEntry.id));
    });
  });

  group('AdhanCatalogCubit — Audio Preview Safety & Local-Only Guarantees', () {
    test('playBuiltInPreview plays asset path via resolver', () async {
      await cubit.playBuiltInPreview(AudioSourceConfig.defaultMishary, isFajr: false);

      expect(audioPlayer.isPlaying, isTrue);
      expect(audioPlayer.currentSource, isA<AssetSource>());
      expect((audioPlayer.currentSource as AssetSource).path, equals('sounds/adhan.mp3'));
      expect(cubit.state.isPreviewPlaying, isTrue);
      expect(cubit.state.playingAudioId, equals(AudioSourceConfig.defaultMishary.id));

      // Toggling stops preview
      await cubit.playBuiltInPreview(AudioSourceConfig.defaultMishary, isFajr: false);
      expect(audioPlayer.isPlaying, isFalse);
      expect(cubit.state.isPreviewPlaying, isFalse);
    });

    test('playRemoteEntryPreview STRICTLY REFUSES remote streaming if not downloaded', () async {
      // Entry is NOT downloaded
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.requiresDownload,
        physicalPath: null,
      );

      await cubit.playRemoteEntryPreview(sampleEntry);

      // CRITICAL ARCHITECTURAL SAFETY INVARIANT:
      // AudioPlayer was NEVER invoked, and a localized notice is shown!
      expect(audioPlayer.isPlaying, isFalse);
      expect(audioPlayer.currentSource, isNull);
      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(cubit.state.userNotice, equals('يجب تنزيل الأذان أولاً للاستماع إليه'));
    });

    test('playRemoteEntryPreview plays from local device file when downloaded', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
      );

      await cubit.playRemoteEntryPreview(sampleEntry);

      expect(audioPlayer.isPlaying, isTrue);
      expect(audioPlayer.currentSource, isA<DeviceFileSource>());
      expect((audioPlayer.currentSource as DeviceFileSource).path, equals('/local/device/path/test.mp3'));
      expect(cubit.state.isPreviewPlaying, isTrue);
      expect(cubit.state.playingAudioId, equals(sampleEntry.id));
    });

    test('stopPreview stops audio and clears preview state', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
      );

      await cubit.playRemoteEntryPreview(sampleEntry);
      expect(cubit.state.isPreviewPlaying, isTrue);

      await cubit.stopPreview();
      expect(audioPlayer.isPlaying, isFalse);
      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(cubit.state.playingAudioId, isNull);
    });
  });

  group('AdhanCatalogCubit — Storage Management & Deletion', () {
    test('deleteDownloadedEntry succeeds, updates status to requiresDownload, clears localSource, refreshes inventory, and emits success notice', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
        localSource: CustomAudioSource(
          id: 'remote:sheikh_test',
          localRelativePath: 'adhan_sounds/remote_sheikh_test.mp3',
          originalFileName: 'remote_sheikh_test.mp3',
          fileSize: 1000000,
          displayName: 'أذان تجريبي رائع',
        ),
      );

      catalogRepo.getCatalogResult = Right(sampleCatalog);
      await cubit.loadCatalog();

      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.ready));
      expect(cubit.state.localSources.containsKey(sampleEntry.id), isTrue);

      storageManager.deleteResult = const Right(null);

      final success = await cubit.deleteDownloadedEntry(sampleEntry);

      expect(success, isTrue);
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.requiresDownload));
      expect(cubit.state.localSources.containsKey(sampleEntry.id), isFalse);
      expect(cubit.state.userNotice, equals('تم حذف الصوت بنجاح من الهاتف'));
      expect(storageManager.lastDeletedPath, contains('remote_sheikh_test'));
    });

    test('deleteDownloadedEntry stops preview if entry is currently playing', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
      );

      await cubit.playRemoteEntryPreview(sampleEntry);
      expect(cubit.state.isPreviewPlaying, isTrue);
      expect(audioPlayer.isPlaying, isTrue);

      storageManager.deleteResult = const Right(null);
      await cubit.deleteDownloadedEntry(sampleEntry);

      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(cubit.state.playingAudioId, isNull);
      expect(audioPlayer.isPlaying, isFalse);
    });

    test('deleteDownloadedEntry fails when locked by active alarm, preserves state, and emits failure message', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
        localSource: CustomAudioSource(
          id: 'remote:sheikh_test',
          localRelativePath: 'adhan_sounds/remote_sheikh_test.mp3',
          originalFileName: 'remote_sheikh_test.mp3',
          fileSize: 1000000,
          displayName: 'أذان تجريبي رائع',
        ),
      );

      catalogRepo.getCatalogResult = Right(sampleCatalog);
      await cubit.loadCatalog();

      storageManager.deleteResult = Left(
        StorageDeletionActiveAlarmFailure(['الفجر', 'العشاء']),
      );

      final success = await cubit.deleteDownloadedEntry(sampleEntry);

      expect(success, isFalse);
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.ready));
      expect(cubit.state.localSources.containsKey(sampleEntry.id), isTrue);
      expect(cubit.state.userNotice, contains('لا يمكن حذف الملف لأنه مستخدم في منبه: الفجر، العشاء'));
    });

    test('previewAbandonedTmpCleanup previews candidate files without deleting them and emits notice', () async {
      storageManager.inventory = AdhanStorageInventory(
        files: const [],
        totalDirectoryBytes: 5120,
        remoteCacheBytes: 4096,
        userCustomBytes: 1024,
        unmanagedBytes: 0,
        stagingTmpBytes: 1024,
        reservedInFlightBytes: 0,
        activeAlarmPaths: const {},
        abandonedTmpFiles: [
          StorageAudioFile(
            relativePath: 'adhan_sounds/.tmp/dl_1.tmp',
            absolutePath: '/app/adhan_sounds/.tmp/dl_1.tmp',
            fileName: 'dl_1.tmp',
            byteLength: 2048,
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            classification: StorageFileClassification.stagingTmp,
            isProtected: false,
            protectedReason: null,
          ),
        ],
        evictionCandidates: const [],
        remoteCacheQuotaBytes: 157286400,
      );

      await cubit.previewAbandonedTmpCleanup();

      expect(cubit.state.userNotice, contains('معاينة: توجد 1 ملفات مؤقتة مهجورة'));
      expect(cubit.state.storageInventory, isNotNull);
    });

    test('refreshStorageInventory updates storage inventory in state', () async {
      storageManager.inventory = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 5120,
        remoteCacheBytes: 4096,
        userCustomBytes: 1024,
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 0,
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 157286400,
      );

      await cubit.refreshStorageInventory();

      expect(cubit.state.storageInventory?.totalDirectoryBytes, equals(5120));
      expect(cubit.state.storageInventory?.userCustomBytes, equals(1024));
    });
  });

  group('AdhanCatalogCubit — Phase 5.3 Quota Enforcement & Storage Integration', () {
    test('5.3-T06: In-flight reservations count towards effective usage', () async {
      storageManager.inventory = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 100 * 1024 * 1024,
        remoteCacheBytes: 90 * 1024 * 1024,
        userCustomBytes: 10 * 1024 * 1024,
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 45 * 1024 * 1024, // 90 + 45 = 135 MiB (85.8% -> Warning)
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
      );

      await cubit.refreshStorageInventory();

      expect(cubit.state.storageInventory?.effectiveRemoteUsageBytes, equals(135 * 1024 * 1024));
      expect(cubit.state.isQuotaWarning, isTrue);
      expect(cubit.state.isQuotaExceeded, isFalse);
    });

    test('5.3-T07: Quota check rejects download if file exceeds available quota', () async {
      storageManager.inventory = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 145 * 1024 * 1024,
        remoteCacheBytes: 145 * 1024 * 1024,
        userCustomBytes: 0,
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 0,
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
      );

      // Remaining is 5 MiB, file is 10 MiB
      final largeEntry = AdhanCatalogEntry(
        id: 'remote:large',
        sheikhName: 'شيخ',
        audioType: AdhanAudioType.general,
        displayName: 'أذان كبير',
        durationSeconds: 180,
        objectKey: 'audio/large.mp3',
        fileSizeBytes: 10 * 1024 * 1024,
        sha256: 'b' * 64,
      );

      await cubit.startDownload(largeEntry);

      expect(cubit.state.userNotice, contains('يتجاوز كوتة كاش الأصوات المتبقية'));
      expect(cubit.state.downloadTasks.containsKey(largeEntry.id), isFalse);
    });

    test('5.3-T08: Quota admission guard prevents starting download when checkQuota denies', () async {
      storageManager.customQuotaCheckResult = const QuotaCheckResult(
        isAllowed: false,
        requiredBytes: 5000000,
        availableQuotaBytes: 2000000,
        currentUsageBytes: 148000000,
        quotaLimitBytes: 150000000,
        deficitBytes: 3000000,
      );

      await cubit.startDownload(sampleEntry);

      expect(cubit.state.userNotice, contains('يتجاوز كوتة كاش الأصوات المتبقية'));
      expect(cubit.state.downloadTasks.containsKey(sampleEntry.id), isFalse);
    });

    test('5.3-T09: User custom audio does not count against remote cache quota', () async {
      storageManager.inventory = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 200 * 1024 * 1024,
        remoteCacheBytes: 50 * 1024 * 1024, // 50 MiB remote
        userCustomBytes: 150 * 1024 * 1024, // 150 MiB user custom
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 0,
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
      );

      await cubit.refreshStorageInventory();

      expect(cubit.state.storageInventory?.effectiveRemoteUsageBytes, equals(50 * 1024 * 1024));
      expect(cubit.state.quotaUsageRatio, closeTo(50 / 150, 0.01));
      expect(cubit.state.isQuotaWarning, isFalse);
      expect(cubit.state.isQuotaExceeded, isFalse);
    });

    test('5.3-T10: Storage inspection failure does not block catalog loading', () async {
      catalogRepo.getCatalogResult = Right(sampleCatalog);
      storageManager.throwOnInspect = true;

      await cubit.loadCatalog();

      expect(cubit.state.status, equals(CatalogStatus.loaded));
      expect(cubit.state.catalog, isNotNull);
      expect(cubit.state.storageStatus, equals(StorageStatus.error));
      expect(cubit.state.storageErrorMessage, contains('Storage disk I/O failure'));
    });

    test('5.3-T11: Monotonic sequence ID ensures latest refresh result wins against out-of-order responses', () async {
      final completer1 = Completer<AdhanStorageInventory>();
      final completer2 = Completer<AdhanStorageInventory>();

      final inv1 = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 1000,
        remoteCacheBytes: 1000,
        userCustomBytes: 0,
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 0,
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
      );

      final inv2 = const AdhanStorageInventory(
        files: [],
        totalDirectoryBytes: 2000,
        remoteCacheBytes: 2000,
        userCustomBytes: 0,
        unmanagedBytes: 0,
        stagingTmpBytes: 0,
        reservedInFlightBytes: 0,
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
      );

      storageManager.pendingInspectCompleter = completer1;
      final future1 = cubit.refreshStorageInventory();

      storageManager.pendingInspectCompleter = completer2;
      final future2 = cubit.refreshStorageInventory();

      // Complete request 2 FIRST (latest request)
      completer2.complete(inv2);
      await future2;
      expect(cubit.state.storageInventory?.totalDirectoryBytes, equals(2000));

      // Complete request 1 LATER (stale response)
      completer1.complete(inv1);
      await future1;

      // Stale response must NOT overwrite the latest result!
      expect(cubit.state.storageInventory?.totalDirectoryBytes, equals(2000));
    });

    test('5.3-T12: Automatic refresh after download success, failure, and cancellation', () async {
      final initialCount = storageManager.inspectCallCount;

      downloadService.downloadResult = Right(
        CustomAudioSource(
          id: sampleEntry.id,
          localRelativePath: 'adhan_sounds/test.mp3',
          originalFileName: 'test.mp3',
          fileSize: sampleEntry.fileSizeBytes,
          displayName: sampleEntry.displayName,
        ),
      );

      await cubit.startDownload(sampleEntry);
      expect(storageManager.inspectCallCount, greaterThan(initialCount));

      final afterSuccess = storageManager.inspectCallCount;
      await cubit.cancelDownload(sampleEntry.id);
      expect(storageManager.inspectCallCount, greaterThan(afterSuccess));
    });

    test('5.3-T14: JIT revalidation prevents deletion if file was assigned to alarm after snapshot', () async {
      storageManager.deleteResult = Left(
        StorageDeletionActiveAlarmFailure(['الفجر']),
      );

      final success = await cubit.deleteStorageFile('adhan_sounds/active_alarm.mp3');

      expect(success, isFalse);
      expect(cubit.state.userNotice, contains('الفجر'));
    });

    test('5.3-T15: Successful deletion of candidate file updates inventory and cubit state', () async {
      resolver.catalogResolutions[sampleEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        physicalPath: '/local/device/path/test.mp3',
      );

      catalogRepo.getCatalogResult = Right(sampleCatalog);
      await cubit.loadCatalog();

      storageManager.deleteResult = const Right(null);
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final success = await cubit.deleteStorageFile('adhan_sounds/$targetFileName');

      expect(success, isTrue);
      expect(cubit.state.playableStatuses[sampleEntry.id], equals(AudioPlayableStatus.requiresDownload));
      expect(cubit.state.userNotice, contains('تم حذف الملف بنجاح'));
    });
  });
}
