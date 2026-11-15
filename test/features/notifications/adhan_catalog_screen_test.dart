import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/adhan_catalog_screen.dart';

class MockCatalogRepository implements BaseAdhanCatalogRepository {
  Either<AdhanCatalogFailure, AdhanCatalog>? result;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    return result ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    return result ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class MockDownloadService implements BaseAudioDownloadService {
  final Map<String, StreamController<AudioDownloadTask>> controllers = {};
  final Map<String, AudioDownloadTask> tasks = {};
  Either<AudioDownloadFailure, CustomAudioSource>? downloadResult;
  Completer<Either<AudioDownloadFailure, CustomAudioSource>>? pendingCompleter;

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
  Set<String> getActiveTempPrefixes() => const {};

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) {
    return _getController(entryId).stream;
  }

  @override
  Future<bool> isAudioDownloaded(String entryId) async {
    return tasks[entryId]?.status == DownloadStatus.completed;
  }

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(AdhanCatalogEntry entry) async {
    if (pendingCompleter != null) {
      return pendingCompleter!.future;
    }
    return downloadResult ?? Left(AudioDownloadNetworkFailure());
  }

  @override
  Future<void> cancelDownload(String entryId) async {
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

class MockPlayableAudioResolver implements BasePlayableAudioResolver {
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
  Future<ResolvedPlayableAudio> resolveIqamaAudio(AudioSourceConfig source) async {
    return audioResolutions['iqama:${source.id}'] ??
        const ResolvedPlayableAudio(
          path: 'assets/sounds/iqama_sound.mp3',
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

class MockStorageManagerService implements BaseAdhanStorageManagerService {
  AdhanStorageInventory inventory = AdhanStorageInventory.empty();
  Either<StorageDeletionFailure, void>? deleteResult;
  String? lastDeletedPath;

  @override
  Future<AdhanStorageInventory> inspectStorage() async => inventory;

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
  Future<List<StorageAudioFile>> getSafeEvictionCandidates() async =>
      inventory.evictionCandidates;

  @override
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(String relativePath, {bool isUserExplicit = false}) async {
    lastDeletedPath = relativePath;
    return deleteResult ?? const Right(null);
  }

  @override
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({Duration ageThreshold = const Duration(minutes: 60)}) async {
    return const StorageCleanupSummary(deletedCount: 1, freedBytes: 2048, deletedFileNames: ['dl_1.tmp']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCatalogRepository mockRepo;
  late MockDownloadService mockDownloadService;
  late MockPlayableAudioResolver mockResolver;
  late MockStorageManagerService mockStorageManager;
  late FakeAudioPlayer mockAudioPlayer;

  final testRemoteEntry = AdhanCatalogEntry(
    id: 'remote:abdulbasit_fajr',
    sheikhName: 'الشيخ عبد الباسط عبد الصمد',
    audioType: AdhanAudioType.fajr,
    displayName: 'أذان الفجر النادر',
    durationSeconds: 195,
    objectKey: 'audio/abdulbasit.mp3',
    fileSizeBytes: 2 * 1024 * 1024,
    sha256: 'b' * 64,
  );

  final testCatalog = AdhanCatalog(
    schemaVersion: 1,
    generatedAt: '2026-11-13T12:00:00Z',
    entries: [testRemoteEntry],
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

    mockRepo = MockCatalogRepository();
    mockDownloadService = MockDownloadService();
    mockResolver = MockPlayableAudioResolver();
    mockStorageManager = MockStorageManagerService();
    mockAudioPlayer = FakeAudioPlayer();

    // Register cubit factory in service locator
    if (sl.isRegistered<AdhanCatalogCubit>()) {
      sl.unregister<AdhanCatalogCubit>();
    }

    sl.registerFactory<AdhanCatalogCubit>(
      () => AdhanCatalogCubit(
        catalogRepository: mockRepo,
        downloadService: mockDownloadService,
        playableAudioResolver: mockResolver,
        storageManagerService: mockStorageManager,
        audioPlayer: mockAudioPlayer,
      ),
    );
  });

  tearDown(() async {
    await mockDownloadService.dispose();
  });

  Widget createWidget({
    AudioSourceConfig currentSelected = AudioSourceConfig.defaultMishary,
    bool isFajr = false,
  }) {
    return MaterialApp(
      home: AdhanCatalogScreen(
        currentSelectedSource: currentSelected,
        isFajr: isFajr,
      ),
    );
  }

  group('AdhanCatalogScreen — UI Rendering & Catalog Integration', () {
    testWidgets('Renders built-in Mishary audio card and remote catalog section', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.requiresDownload,
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Built-in section
      expect(find.text('الأصوات المدمجة'), findsOneWidget);
      expect(find.text('الشيخ مشاري راشد العفاسي'), findsOneWidget);

      // Remote section
      expect(find.text('مكتبة الأذان السحابية'), findsOneWidget);
      expect(find.text('الشيخ عبد الباسط عبد الصمد'), findsOneWidget);
      expect(find.text('أذان الفجر النادر'), findsOneWidget);
      expect(find.text('أذان الفجر'), findsWidgets);
      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
    });

    testWidgets('Shows offline banner when catalog is offline or unconfigured', (tester) async {
      mockRepo.result = Left(CatalogNetworkFailure(message: 'خطأ اتصال'));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_off_rounded), findsWidgets);
      expect(find.textContaining('أنت في وضع عدم الاتصال'), findsOneWidget);
    });

    testWidgets('Tapping preview on non-downloaded entry shows warning SnackBar and does NOT play', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.requiresDownload,
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Remote entry play button is the second play icon
      final playIcons = find.byIcon(Icons.play_circle_outline_rounded);
      expect(playIcons, findsOneWidget);

      await tester.tap(playIcons);
      await tester.pump();

      // Verify SnackBar warning appears
      expect(find.text('يجب تنزيل الأذان أولاً للاستماع إليه'), findsOneWidget);
      expect(mockAudioPlayer.isPlaying, isFalse);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Downloaded entry displays "اختيار" button and returns CustomAudioSource on tap', (tester) async {
      mockRepo.result = Right(testCatalog);

      const downloadedSource = CustomAudioSource(
        id: 'custom:remote:abdulbasit_fajr',
        displayName: 'أذان الفجر النادر',
        localRelativePath: 'adhan_sounds/remote_abdulbasit.mp3',
        originalFileName: 'abdulbasit.mp3',
        fileSize: 2000000,
      );

      mockResolver.catalogResolutions[testRemoteEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: downloadedSource,
        physicalPath: '/storage/adhan_sounds/remote_abdulbasit.mp3',
      );

      AudioSourceConfig? returnedSource;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedSource = await Navigator.of(context).push<AudioSourceConfig>(
                  MaterialPageRoute(
                    builder: (_) => const AdhanCatalogScreen(
                      currentSelectedSource: AudioSourceConfig.defaultMishary,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      // Open screen
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Find "اختيار" on the downloaded remote entry
      final selectButtons = find.widgetWithText(OutlinedButton, 'اختيار');
      expect(selectButtons, findsOneWidget); // Mishary is selected, so only remote has OutlinedButton

      await tester.tap(selectButtons);
      await tester.pumpAndSettle();

      // Verify route popped and returned CustomAudioSource!
      expect(returnedSource, isNotNull);
      expect(returnedSource, isA<CustomAudioSource>());
      expect((returnedSource as CustomAudioSource).id, equals('custom:remote:abdulbasit_fajr'));
    });

    testWidgets('Active download shows byte progress and percentage', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = const CatalogEntryResolution(
        status: AudioPlayableStatus.requiresDownload,
      );

      mockDownloadService.tasks[testRemoteEntry.id] = AudioDownloadTask.downloading(
        entryId: testRemoteEntry.id,
        progress: DownloadProgress.determinate(receivedBytes: 1048576, totalBytes: 2097152),
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is LinearProgressIndicator && w.value == 0.5),
        findsOneWidget,
      );
      expect(find.text('50%'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);

      // Tapping cancel calls cancelDownload on cubit
      await tester.tap(find.byIcon(Icons.cancel_rounded));
      await tester.pump();
      expect(mockDownloadService.tasks[testRemoteEntry.id]?.status, equals(DownloadStatus.cancelled));
    });

    testWidgets('Phase 5.2 — Downloaded entry displays delete button and tapping shows confirmation dialog', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: CustomAudioSource(
          id: 'custom:${testRemoteEntry.id}',
          displayName: testRemoteEntry.displayName,
          localRelativePath: 'adhan_sounds/remote_abdulbasit_fajr_${'b' * 24}.mp3',
          originalFileName: 'abdulbasit.mp3',
          fileSize: 2097152,
        ),
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Verify delete button is displayed next to "اختيار"
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'اختيار'), findsOneWidget);

      // Tap delete button -> Confirmation dialog appears
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('حذف الأذان من الهاتف'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.text('حذف'), findsOneWidget);

      // Tap cancel -> dialog dismisses without delete
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('حذف الأذان من الهاتف'), findsNothing);
      expect(mockStorageManager.lastDeletedPath, isNull);
    });

    testWidgets('Phase 5.2 — Confirming delete invokes delete on cubit and updates UI state', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: CustomAudioSource(
          id: 'custom:${testRemoteEntry.id}',
          displayName: testRemoteEntry.displayName,
          localRelativePath: 'adhan_sounds/remote_abdulbasit_fajr_${'b' * 24}.mp3',
          originalFileName: 'abdulbasit.mp3',
          fileSize: 2097152,
        ),
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap delete button
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Confirm delete
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();

      // Verify service was called
      expect(mockStorageManager.lastDeletedPath, contains('remote_abdulbasit_fajr'));
      // Notice shown
      expect(find.text('تم حذف الصوت بنجاح من الهاتف'), findsOneWidget);
    });

    testWidgets('Phase 5.2 — Active alarm audio displays warning SnackBar when delete is tapped', (tester) async {
      final targetRelPath = 'adhan_sounds/remote_abdulbasit_fajr_${'b' * 24}.mp3';
      mockRepo.result = Right(testCatalog);
      mockResolver.catalogResolutions[testRemoteEntry.id] = CatalogEntryResolution(
        status: AudioPlayableStatus.ready,
        localSource: CustomAudioSource(
          id: 'custom:${testRemoteEntry.id}',
          displayName: testRemoteEntry.displayName,
          localRelativePath: targetRelPath,
          originalFileName: 'abdulbasit.mp3',
          fileSize: 2097152,
        ),
      );

      // Lock this path in activeAlarmPaths
      mockStorageManager.inventory = AdhanStorageInventory(
        totalDirectoryBytes: 2097152,
        remoteCacheBytes: 2097152,
        userCustomBytes: 0,
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: const [],
        activeAlarmPaths: {targetRelPath},
        abandonedTmpFiles: const [],
        evictionCandidates: const [],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap delete button on locked audio
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Dialog does NOT open; SnackBar warning is displayed
      expect(find.text('حذف الأذان من الهاتف'), findsNothing);
      expect(find.text('لا يمكن حذف هذا الأذان لأنه مخصص لمنبه إحدى الصلوات'), findsOneWidget);
    });

    testWidgets('Phase 5.2 — Tapping storage icon in AppBar opens storage details modal', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = AdhanStorageInventory(
        totalDirectoryBytes: 10 * 1024 * 1024,
        remoteCacheBytes: 8 * 1024 * 1024,
        userCustomBytes: 2 * 1024 * 1024,
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: const [],
        activeAlarmPaths: const {},
        abandonedTmpFiles: const [],
        evictionCandidates: const [],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap storage icon in AppBar
      expect(find.byIcon(Icons.pie_chart_outline_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pie_chart_outline_rounded));
      await tester.pumpAndSettle();

      // Modal bottom sheet appears
      expect(find.text('إدارة مساحة أصوات الأذان'), findsOneWidget);
      expect(find.textContaining('إجمالي مساحة مجلد adhan_sounds/'), findsOneWidget);
      expect(find.textContaining('كاش الأصوات السحابية'), findsWidgets);
      expect(find.text('أصوات المستخدم المخصصة'), findsOneWidget);
      expect(find.text('إغلاق'), findsOneWidget);

      await tester.ensureVisible(find.text('إغلاق'));
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
      expect(find.text('إدارة مساحة أصوات الأذان'), findsNothing);
    });

    testWidgets('Phase 5.2 — Abandoned tmp files shown as Preview Info without physical deletion button', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = AdhanStorageInventory(
        totalDirectoryBytes: 10 * 1024 * 1024,
        remoteCacheBytes: 8 * 1024 * 1024,
        userCustomBytes: 2 * 1024 * 1024,
        stagingTmpBytes: 4096,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: const [],
        activeAlarmPaths: const {},
        abandonedTmpFiles: [
          StorageAudioFile(
            relativePath: 'adhan_sounds/.tmp/dl_1.tmp',
            absolutePath: '/app/adhan_sounds/.tmp/dl_1.tmp',
            fileName: 'dl_1.tmp',
            byteLength: 4096,
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            classification: StorageFileClassification.stagingTmp,
            isProtected: false,
            protectedReason: null,
          ),
        ],
        evictionCandidates: const [],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Open storage details modal
      await tester.tap(find.byIcon(Icons.pie_chart_outline_rounded));
      await tester.pumpAndSettle();

      // Verify informational preview is displayed
      expect(find.textContaining('مرشحة للتنظيف التلقائي'), findsOneWidget);
      // Strictly verify NO physical deletion button exists!
      expect(find.text('تنظيف الآن'), findsNothing);
    });

    testWidgets('5.3-T01 & 5.3-T16: Normal banner rendered at 0% and empty inventory shows 0.0 / 150 MiB', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 0,
        remoteCacheBytes: 0,
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
      expect(find.textContaining('كاش الأصوات السحابية: 0.0 / 150 ميجابايت'), findsOneWidget);
    });

    testWidgets('5.3-T02: Normal banner rendered when usage is below warning threshold (e.g. 50 MiB)', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 50 * 1024 * 1024,
        remoteCacheBytes: 50 * 1024 * 1024,
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
      expect(find.textContaining('كاش الأصوات السحابية: 50.0 / 150 ميجابايت'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('5.3-T03: Warning banner rendered when usage is >= 85%', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 130 * 1024 * 1024,
        remoteCacheBytes: 130 * 1024 * 1024, // 130 / 150 = 86.7%
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('تحذير: اقتراب امتلاء كاش الأصوات'), findsOneWidget);
    });

    testWidgets('5.3-T04: Warning banner rendered when remaining headroom is < 22.5 MiB', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 129 * 1024 * 1024,
        remoteCacheBytes: 129 * 1024 * 1024, // remaining = 21 MiB (< 22.5 MiB)
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('تحذير: اقتراب امتلاء كاش الأصوات'), findsOneWidget);
    });

    testWidgets('5.3-T05: Exceeded banner rendered when usage is >= 100%', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 150 * 1024 * 1024,
        remoteCacheBytes: 150 * 1024 * 1024, // 100%
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.textContaining('تم بلوغ الحد الأقصى لكاش الأصوات'), findsOneWidget);
      expect(find.textContaining('التنزيلات متوقفة حتى تحرير مساحة'), findsOneWidget);
    });

    testWidgets('5.3-T08: Trailing download button is disabled with alert SnackBar when quota is exceeded', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 155 * 1024 * 1024,
        remoteCacheBytes: 155 * 1024 * 1024,
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

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Find download button
      final downloadBtn = find.byIcon(Icons.cloud_download_outlined);
      expect(downloadBtn, findsOneWidget);

      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      // SnackBar alert explains quota is full
      expect(find.textContaining('لا يمكن بدء تنزيل جديد: تم بلوغ الحد الأقصى لكاش الأصوات'), findsOneWidget);
    });

    testWidgets('5.3-T09: Storage modal displays user custom sounds as independent and exempt from 150 MiB quota', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = const AdhanStorageInventory(
        totalDirectoryBytes: 120 * 1024 * 1024,
        remoteCacheBytes: 20 * 1024 * 1024,
        userCustomBytes: 100 * 1024 * 1024, // 100 MiB user custom
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: [],
        activeAlarmPaths: {},
        abandonedTmpFiles: [],
        evictionCandidates: [],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap details button in quota banner
      await tester.tap(find.text('تفاصيل الذاكرة'));
      await tester.pumpAndSettle();

      expect(find.textContaining('أصواتك المخصصة مستقلة تماماً ومعفاة من كوتة الكاش (150 ميجابايت)'), findsOneWidget);
      expect(find.text('100.0 ميجابايت'), findsOneWidget);
    });

    testWidgets('5.3-T13: Protected file in modal displays lock icon and prayer names without delete button', (tester) async {
      mockRepo.result = Right(testCatalog);
      mockStorageManager.inventory = AdhanStorageInventory(
        totalDirectoryBytes: 20 * 1024 * 1024,
        remoteCacheBytes: 20 * 1024 * 1024,
        userCustomBytes: 0,
        stagingTmpBytes: 0,
        unmanagedBytes: 0,
        reservedInFlightBytes: 0,
        remoteCacheQuotaBytes: 150 * 1024 * 1024,
        files: [
          StorageAudioFile(
            relativePath: 'adhan_sounds/remote_fajr.mp3',
            absolutePath: '/app/adhan_sounds/remote_fajr.mp3',
            fileName: 'remote_fajr.mp3',
            byteLength: 5 * 1024 * 1024,
            lastModified: DateTime.now(),
            classification: StorageFileClassification.remoteCache,
            isProtected: true,
            protectedReason: 'صلاة الفجر',
          ),
        ],
        activeAlarmPaths: const {'adhan_sounds/remote_fajr.mp3'},
        abandonedTmpFiles: const [],
        evictionCandidates: const [],
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('تفاصيل الذاكرة'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('remote_fajr.mp3'), findsOneWidget);
      expect(find.textContaining('صلاة الفجر'), findsOneWidget);
      expect(find.text('محمي'), findsOneWidget);
      // No delete button in safe eviction list
      expect(find.text('لا توجد أصوات سحابية قابلة للحذف.'), findsOneWidget);
    });
  });
}
