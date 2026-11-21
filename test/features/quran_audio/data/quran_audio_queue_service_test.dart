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

class FakeQuranAudioDownloadService implements BaseQuranAudioDownloadService {
  final Map<int, SingleSurahDownloadResult> cannedResults = {};
  final List<int> requestedSurahs = [];
  int downloadDelayMs = 0;
  bool pauseCalled = false;
  bool cancelCalled = false;

  @override
  Future<SingleSurahDownloadResult> downloadSurahAndWait({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    void Function(DownloadProgress progress)? onProgress,
    bool skipCoordinatorReservation = false,
  }) async {
    requestedSurahs.add(surahNumber);
    if (onProgress != null) {
      onProgress(DownloadProgress(
        surahNumber: surahNumber,
        reciterId: reciterId,
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 500,
        expectedTotalBytes: expectedTotalBytes ?? 1000,
      ));
    }
    if (downloadDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: downloadDelayMs));
    }
    if (pauseCalled) {
      return SingleSurahDownloadResult.paused(
        surahNumber: surahNumber,
        reciterId: reciterId,
        downloadedBytes: 500,
      );
    }
    if (cancelCalled) {
      return SingleSurahDownloadResult.cancelled(
        surahNumber: surahNumber,
        reciterId: reciterId,
      );
    }
    return cannedResults[surahNumber] ??
        SingleSurahDownloadResult.completed(
          surahNumber: surahNumber,
          reciterId: reciterId,
          filePath: '/path/$surahNumber.mp3',
          totalBytes: 1000,
          sha256: 'hash_$surahNumber',
        );
  }

  @override
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    bool skipCoordinatorReservation = false,
  }) {
    return Stream.value(DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.completed,
      downloadedBytes: 1000,
      expectedTotalBytes: 1000,
    ));
  }

  @override
  Future<void> pauseDownload(int surahNumber, String reciterId) async {
    pauseCalled = true;
  }

  @override
  Future<void> cancelDownload(int surahNumber, String reciterId) async {
    cancelCalled = true;
  }

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
  late FakeQuranAudioDownloadService downloadService;
  late QuranAudioLocalDataSourceImpl localDataSource;
  late QuranAudioStorageService storageService;
  late QuranAudioDownloadCoordinator coordinator;
  late QuranAudioQueueService queueService;
  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('quran_queue_test_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    database = QuranAudioDatabase.inMemory();
    await database.init();
    queueRepository = AudioDownloadQueueRepositoryImpl(database: database);

    localDataSource = QuranAudioLocalDataSourceImpl(
      database: database,
      prefs: prefs,
    );
    storageService = QuranAudioStorageService(
      customBaseDirectoryProvider: () => testDir,
    );
    coordinator = QuranAudioDownloadCoordinator();
    downloadService = FakeQuranAudioDownloadService();

    queueService = QuranAudioQueueService(
      queueRepository: queueRepository,
      downloadService: downloadService,
      localDataSource: localDataSource,
      storageService: storageService,
      coordinator: coordinator,
    );
  });

  tearDown(() async {
    queueService.dispose();
    await database.close();
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('QA.6 Phase 6.4 - QuranAudioQueueService Tests', () {
    test('startQueue creates 114 items and starts processing sequentially', () async {
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
        expectedSurahSizes: List.filled(114, 1000),
      );

      expect(queue.id, startsWith('queue_7_'));
      expect(queue.totalItems, equals(114));
      expect(queue.items.length, equals(114));
      expect(coordinator.isBusy, isTrue, reason: 'Coordinator must hold queue reservation');

      // Wait a moment for worker to process initial items
      await Future.delayed(const Duration(milliseconds: 100));

      expect(downloadService.requestedSurahs, isNotEmpty);
      expect(downloadService.requestedSurahs.first, equals(1), reason: 'Must start from Surah 1');
    });

    test('startQueue pre-checks verified completed Surahs and marks them skipped', () async {
      // Create completed file & record for Surah 1 & 2
      final now = DateTime.now();
      final surah1File = await storageService.resolveSurahFile(1, '7');
      await surah1File.parent.create(recursive: true);
      await surah1File.writeAsBytes(List.filled(500, 1));

      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: '7/001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 500,
        sha256: 'abc123sha',
        transferIntegrityVerified: true,
        downloadedAt: now,
        completedAt: now,
      ));

      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      final item1 = queue.items.firstWhere((i) => i.surahNumber == 1);
      expect(item1.status, equals(QuranDownloadQueueItemStatus.skipped));
      expect(queue.completedItems, equals(1));

      await Future.delayed(const Duration(milliseconds: 80));

      // Worker should have skipped Surah 1 and started download on Surah 2!
      expect(downloadService.requestedSurahs.contains(1), isFalse);
      expect(downloadService.requestedSurahs.contains(2), isTrue);
    });

    test('pauseQueue halts scheduling, calls pauseDownload, and releases coordinator', () async {
      downloadService.downloadDelayMs = 200;
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      await queueService.pauseQueue(queue.id);

      expect(coordinator.isBusy, isFalse, reason: 'Coordinator ticket must be released on pause');

      final pausedQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(pausedQueue!.status, equals(QuranDownloadQueueStatus.paused));
    });

    test('cancelQueue marks queue cancelled, calls cancelDownload, and releases coordinator', () async {
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      await queueService.cancelQueue(queue.id);

      expect(coordinator.isBusy, isFalse);
      final cancelledQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(cancelledQueue!.status, equals(QuranDownloadQueueStatus.cancelled));
    });

    test('retryQueue recovers failed items and resumes worker execution', () async {
      // Configure Surah 1 to fail
      downloadService.cannedResults[1] = SingleSurahDownloadResult.failed(
        surahNumber: 1,
        reciterId: '7',
        errorMessage: 'Connection reset',
      );

      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      // Wait for failure
      await Future.delayed(const Duration(milliseconds: 80));

      var failedQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(failedQueue!.status, equals(QuranDownloadQueueStatus.failed));
      expect(coordinator.isBusy, isFalse);

      // Change Surah 1 to succeed on retry
      downloadService.cannedResults[1] = SingleSurahDownloadResult.completed(
        surahNumber: 1,
        reciterId: '7',
        filePath: '/path/1.mp3',
        totalBytes: 1000,
        sha256: 'sha1',
      );

      await queueService.retryQueue(
        queueId: queue.id,
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      expect(coordinator.isBusy, isTrue);

      await Future.delayed(const Duration(milliseconds: 80));

      final retriedQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      final item1 = retriedQueue!.items.firstWhere((i) => i.surahNumber == 1);
      expect(item1.status, equals(QuranDownloadQueueItemStatus.completed));
    });

    test('recoverInterruptedQueuesOnStartup normalizes running queue and incomplete item to paused', () async {
      downloadService.downloadDelayMs = 100;
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      // Simulate a sudden crash while queue is running
      queueService.dispose();

      // Create a fresh queue service instance as if app just restarted
      final freshCoordinator = QuranAudioDownloadCoordinator();
      final recoveredService = QuranAudioQueueService(
        queueRepository: queueRepository,
        downloadService: downloadService,
        localDataSource: localDataSource,
        storageService: storageService,
        coordinator: freshCoordinator,
      );

      // Before recovery, the database has queue in running
      final preRecoveryQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(preRecoveryQueue!.status, equals(QuranDownloadQueueStatus.running));

      // Execute crash recovery
      await recoveredService.recoverInterruptedQueuesOnStartup();

      // Verify queue is normalized to paused
      final postRecoveryQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(postRecoveryQueue!.status, equals(QuranDownloadQueueStatus.paused));

      // Verify running items were normalized to paused (or completed if finished)
      for (final item in postRecoveryQueue.items) {
        expect(item.status.isRunning, isFalse, reason: 'No item should remain in running status after recovery');
      }

      // Verify restored progress was emitted
      expect(recoveredService.currentProgress, isNotNull);
      expect(recoveredService.currentProgress!.status, equals(QuranDownloadQueueStatus.paused));
    });

    test('recoverInterruptedQueuesOnStartup authoritatively completes verified items', () async {
      downloadService.downloadDelayMs = 100;
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      // Halt worker immediately
      queueService.dispose();

      // Simulate item 5 was running, but actually finished and committed to disk & local DB before crash
      final surah5File = await storageService.resolveSurahFile(5, '7');
      await surah5File.parent.create(recursive: true);
      await surah5File.writeAsBytes(List.filled(2048, 1));

      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 5,
        reciterId: '7',
        status: AudioDownloadStatus.completed,
        localRelativePath: QuranAudioStorageService.buildRelativePath(5, '7'),
        actualSizeBytes: 2048,
        sha256: 'sha5',
        transferIntegrityVerified: true,
        completedAt: DateTime.now(),
      ));

      // Set item 5 to running in queue to simulate crash mid-loop
      await queueRepository.updateQueueItemStatus(
        queueId: queue.id,
        surahNumber: 5,
        status: QuranDownloadQueueItemStatus.running,
      );

      queueService.dispose();

      // App restart
      final freshCoordinator = QuranAudioDownloadCoordinator();
      final freshService = QuranAudioQueueService(
        queueRepository: queueRepository,
        downloadService: downloadService,
        localDataSource: localDataSource,
        storageService: storageService,
        coordinator: freshCoordinator,
      );

      await freshService.recoverInterruptedQueuesOnStartup();

      final recoveredQueue = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      final item5 = recoveredQueue!.items.firstWhere((i) => i.surahNumber == 5);

      expect(item5.status, equals(QuranDownloadQueueItemStatus.completed));
      expect(item5.downloadedBytes, equals(2048));
    });

    test('resumeQueue transitions paused queue to running and resumes execution', () async {
      downloadService.downloadDelayMs = 20;
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      await Future.delayed(const Duration(milliseconds: 30));
      await queueService.pauseQueue(queue.id);

      var q = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(q!.status, equals(QuranDownloadQueueStatus.paused));
      expect(coordinator.isBusy, isFalse);

      // Resume
      await queueService.resumeQueue(
        queueId: queue.id,
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      expect(coordinator.isBusy, isTrue);
      q = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(q!.status, equals(QuranDownloadQueueStatus.running));
    });

    test('pauseQueue and cancelQueue are strictly idempotent', () async {
      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://example.com/$surah.mp3',
      );

      // Call pause twice
      await queueService.pauseQueue(queue.id);
      await queueService.pauseQueue(queue.id);

      var q = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(q!.status, equals(QuranDownloadQueueStatus.paused));

      // Call cancel twice
      await queueService.cancelQueue(queue.id);
      await queueService.cancelQueue(queue.id);

      q = (await queueRepository.getQueueById(queue.id)).getOrElse(() => null);
      expect(q!.status, equals(QuranDownloadQueueStatus.cancelled));
      expect(coordinator.isBusy, isFalse);
    });
  });
}
