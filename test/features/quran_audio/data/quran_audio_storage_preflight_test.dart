import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_queue_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_coordinator.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_queue_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_status.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/single_surah_download_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDownloadService implements BaseQuranAudioDownloadService {
  @override
  Future<SingleSurahDownloadResult> downloadSurahAndWait({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    void Function(DownloadProgress progress)? onProgress,
    bool skipCoordinatorReservation = false,
  }) async {
    return SingleSurahDownloadResult.completed(
      surahNumber: surahNumber,
      reciterId: reciterId,
      filePath: '/path/$surahNumber.mp3',
      totalBytes: expectedTotalBytes ?? 1024,
      sha256: 'sha_$surahNumber',
    );
  }

  @override
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    bool skipCoordinatorReservation = false,
  }) =>
      const Stream.empty();

  @override
  Future<void> pauseDownload(int surahNumber, String reciterId) async {}

  @override
  Future<void> cancelDownload(int surahNumber, String reciterId) async {}

  @override
  Future<void> retryDownload({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  }) async {}

  @override
  DownloadProgress? getProgress(int surahNumber, String reciterId) => null;

  @override
  Stream<DownloadProgress> watchProgress(int surahNumber, String reciterId) =>
      const Stream.empty();

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BaseQuranAudioDatabase database;
  late AudioDownloadQueueRepositoryImpl queueRepository;
  late _FakeDownloadService downloadService;
  late QuranAudioLocalDataSourceImpl localDataSource;
  late QuranAudioDownloadCoordinator coordinator;
  late Directory testDir;
  int? mockAvailableDiskSpace;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('quran_preflight_test_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    database = QuranAudioDatabase.inMemory();
    await database.init();
    queueRepository = AudioDownloadQueueRepositoryImpl(database: database);

    localDataSource = QuranAudioLocalDataSourceImpl(
      database: database,
      prefs: prefs,
    );
    coordinator = QuranAudioDownloadCoordinator();
    downloadService = _FakeDownloadService();
    mockAvailableDiskSpace = 500 * 1024 * 1024; // 500 MB default
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  QuranAudioStorageService createStorageService() {
    return QuranAudioStorageService(
      customBaseDirectoryProvider: () => testDir,
      customDiskSpaceProvider: () async => mockAvailableDiskSpace,
    );
  }

  QuranAudioQueueService createQueueService(QuranAudioStorageService storage) {
    return QuranAudioQueueService(
      queueRepository: queueRepository,
      downloadService: downloadService,
      localDataSource: localDataSource,
      storageService: storage,
      coordinator: coordinator,
    );
  }

  group('QA.6 Phase 6.6 - Storage Preflight & Indeterminate Sizing Tests', () {
    test('checkStoragePreflight returns sufficient when space exceeds exact sum + 25 MB floor', () async {
      final storage = createStorageService();
      final service = createQueueService(storage);

      // 114 Surahs each of 1 MB (1,048,576 B)
      final expectedSizes = List.filled(114, 1024 * 1024);
      final rawSum = 114 * 1024 * 1024;
      final expectedRequired = rawSum + QuranAudioStorageService.kSafetyFloorBytes;

      mockAvailableDiskSpace = expectedRequired + 10 * 1024 * 1024; // 10 MB headroom

      final result = await service.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: expectedSizes,
      );

      expect(result.isSufficient, isTrue);
      expect(result.requiredBytes, equals(expectedRequired));
      expect(result.availableBytes, equals(mockAvailableDiskSpace));
    });

    test('checkStoragePreflight returns insufficient when space is below exact sum + 25 MB floor', () async {
      final storage = createStorageService();
      final service = createQueueService(storage);

      final expectedSizes = List.filled(114, 1024 * 1024);
      final rawSum = 114 * 1024 * 1024;
      final expectedRequired = rawSum + QuranAudioStorageService.kSafetyFloorBytes;

      mockAvailableDiskSpace = expectedRequired - 1; // 1 byte short

      final result = await service.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: expectedSizes,
      );

      expect(result.isInsufficient, isTrue);
      expect(result.requiredBytes, equals(expectedRequired));
      expect(result.availableBytes, equals(mockAvailableDiskSpace));
      expect(result.message, contains('المساحة التخزينية المتاحة غير كافية'));
    });

    test('checkStoragePreflight excludes already verified completed Surahs from required calculation', () async {
      final storage = createStorageService();
      final service = createQueueService(storage);

      // Pre-download Surah 1 (1 MB)
      final surah1File = await storage.resolveSurahFile(1, '7');
      await surah1File.parent.create(recursive: true);
      await surah1File.writeAsBytes(List.filled(1024 * 1024, 1));

      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.completed,
        localRelativePath: QuranAudioStorageService.buildRelativePath(1, '7'),
        actualSizeBytes: 1024 * 1024,
        sha256: 'sha1',
        transferIntegrityVerified: true,
        completedAt: DateTime.now(),
      ));

      // 114 Surahs each of 1 MB
      final expectedSizes = List.filled(114, 1024 * 1024);
      // Surah 1 is excluded: 113 * 1 MB + 25 MB floor
      final expectedRequired = (113 * 1024 * 1024) + QuranAudioStorageService.kSafetyFloorBytes;

      mockAvailableDiskSpace = expectedRequired + 5 * 1024 * 1024;

      final result = await service.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: expectedSizes,
      );

      expect(result.isSufficient, isTrue);
      expect(result.requiredBytes, equals(expectedRequired));
    });

    test('checkStoragePreflight returns indeterminate when any pending Surah has null expected size', () async {
      final storage = createStorageService();
      final service = createQueueService(storage);

      final expectedSizes = List<int?>.filled(114, 1024 * 1024);
      expectedSizes[10] = null; // Surah 11 size is indeterminate

      final result = await service.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: expectedSizes,
      );

      expect(result.isIndeterminate, isTrue);
      expect(result.availableBytes, equals(mockAvailableDiskSpace));
      expect(result.message, contains('حجم بعض السور غير محدد مسبقًا'));
    });

    test('Runtime disk space safety floor halts queue when available space drops below 25 MB', () async {
      mockAvailableDiskSpace = 20 * 1024 * 1024; // 20 MB (< 25 MB safety floor)
      final storage = createStorageService();
      final service = createQueueService(storage);

      final queue = await service.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      final failedQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(failedQueue!.status, equals(QuranDownloadQueueStatus.failed));
      expect(coordinator.isBusy, isFalse);

      final item1 = failedQueue.items.firstWhere((i) => i.surahNumber == 1);
      expect(item1.status, equals(QuranDownloadQueueItemStatus.failed));
      expect(item1.lastError, contains('المساحة التخزينية المتاحة أقل من الحد الأدنى الآمن'));
    });
  });
}
