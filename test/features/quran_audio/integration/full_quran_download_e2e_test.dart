import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_queue_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_coordinator.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_queue_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_item.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_status.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/single_surah_download_result.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_quran_audio_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_reciters_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_surah_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/save_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_cubit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeQuranAudioRepository implements BaseQuranAudioRepository {
  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({bool forceRefresh = false}) async {
    return Right([
      AudioReciter(
        id: '7',
        name: 'Mishari Rashid al-`Afasy',
        arabicName: 'مشاري راشد العفاسي',
      ),
      AudioReciter(
        id: '1',
        name: 'AbdulBaset AbdulSamad',
        arabicName: 'عبد الباسط عبد الصمد',
      ),
    ]);
  }

  @override
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter() async {
    final list = await getReciters();
    return Right(list.getOrElse(() => [])[0]);
  }

  @override
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId) async {
    return const Right(null);
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    return Right(
      SurahAudio(
        surahNumber: surahNumber,
        reciterId: reciterId,
        audioUrl: 'https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/$surahNumber.mp3',
        durationMs: 30000,
        ayahTimings: const [],
      ),
    );
  }

  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  }) async => const Right([]);

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async => const Right(null);

  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async => const Right(null);
}

class _FakePlayer implements QuranAudioPlayer {
  final StreamController<QuranPlaybackStatus> statusController = StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> posController = StreamController<Duration>.broadcast();
  final StreamController<Duration?> durController = StreamController<Duration?>.broadcast();

  QuranPlaybackStatus _status = QuranPlaybackStatus.idle;
  Duration _pos = Duration.zero;
  Duration? _dur;
  SurahAudio? _track;
  AudioRepeatMode _repeatMode = AudioRepeatMode.continuous;
  int? _repeatCount;

  @override
  Stream<QuranPlaybackStatus> get playbackStatusStream => statusController.stream;
  @override
  Stream<Duration> get positionStream => posController.stream;
  @override
  Stream<Duration?> get durationStream => durController.stream;
  @override
  QuranPlaybackStatus get status => _status;
  @override
  bool get isPlaying => _status == QuranPlaybackStatus.playing;
  @override
  Duration get currentPosition => _pos;
  @override
  Duration? get duration => _dur;
  @override
  SurahAudio? get currentTrack => _track;
  @override
  AudioRepeatMode get repeatMode => _repeatMode;
  @override
  int? get repeatCount => _repeatCount;
  bool get isActuallyPlaying => false;

  @override
  Future<void> loadSurah({required SurahAudio surahAudio, Duration? startPosition, String? localFilePath}) async {
    _track = surahAudio;
    _dur = Duration(milliseconds: surahAudio.durationMs);
    _status = QuranPlaybackStatus.idle;
    statusController.add(_status);
  }

  @override
  Future<void> play() async {
    _status = QuranPlaybackStatus.playing;
    statusController.add(_status);
  }

  @override
  Future<void> pause() async {
    _status = QuranPlaybackStatus.paused;
    statusController.add(_status);
  }

  @override
  Future<void> stop() async {
    _status = QuranPlaybackStatus.idle;
    statusController.add(_status);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _pos = position;
    posController.add(_pos);
  }

  @override
  Future<void> setVolume(double newVolume) async {}

  @override
  Future<void> setRepeatMode(AudioRepeatMode mode, {int? rangeStartAyah, int? rangeEndAyah, int? repeatCount}) async {
    _repeatMode = mode;
    _repeatCount = repeatCount;
  }

  @override
  Future<void> dispose() async {
    await statusController.close();
    await posController.close();
    await durController.close();
  }
}

class _ControllableFakeDownloadService implements BaseQuranAudioDownloadService {
  int downloadDelayMs = 0;
  bool isPaused = false;
  final Map<int, SingleSurahDownloadResult> cannedResults = {};

  @override
  Future<SingleSurahDownloadResult> downloadSurahAndWait({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    void Function(DownloadProgress progress)? onProgress,
    bool skipCoordinatorReservation = false,
  }) async {
    if (onProgress != null) {
      onProgress(DownloadProgress(
        surahNumber: surahNumber,
        reciterId: reciterId,
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 250,
        expectedTotalBytes: expectedTotalBytes ?? 500,
      ));
    }

    if (downloadDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: downloadDelayMs));
    }

    if (isPaused) {
      return SingleSurahDownloadResult.paused(
        surahNumber: surahNumber,
        reciterId: reciterId,
        downloadedBytes: 250,
      );
    }

    return cannedResults[surahNumber] ??
        SingleSurahDownloadResult.completed(
          surahNumber: surahNumber,
          reciterId: reciterId,
          filePath: '/mock/path/$surahNumber.mp3',
          totalBytes: expectedTotalBytes ?? 500,
          sha256: 'sha256_$surahNumber',
        );
  }

  @override
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    bool skipCoordinatorReservation = false,
  }) => const Stream.empty();

  @override
  Future<void> pauseDownload(int surahNumber, String reciterId) async {
    isPaused = true;
  }

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
  Stream<DownloadProgress> watchProgress(int surahNumber, String reciterId) => const Stream.empty();

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late QuranAudioDatabase db;
  late QuranAudioLocalDataSourceImpl localDataSource;
  late QuranAudioStorageService storageService;
  late AudioDownloadRepositoryImpl downloadRepo;
  late AudioDownloadQueueRepositoryImpl queueRepo;
  late QuranAudioDownloadCoordinator coordinator;
  late _FakeQuranAudioRepository fakeQuranRepo;
  late _FakePlayer fakePlayer;
  late QuranAudioHandler handler;
  late AyahTrackingEngine trackingEngine;
  late SharedPreferences prefs;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('quran_audio_qa6_e2e_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    db = QuranAudioDatabase.inMemory();
    await db.init();
    localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);
    storageService = QuranAudioStorageService(
      customBaseDirectoryProvider: () => testDir,
    );
    downloadRepo = AudioDownloadRepositoryImpl(
      localDataSource: localDataSource,
      storageService: storageService,
    );
    queueRepo = AudioDownloadQueueRepositoryImpl(database: db);
    coordinator = QuranAudioDownloadCoordinator();

    fakeQuranRepo = _FakeQuranAudioRepository();
    fakePlayer = _FakePlayer();
    handler = QuranAudioHandler(
      player: fakePlayer,
      getSurahAudioUseCase: GetSurahAudioUseCase(fakeQuranRepo),
    );
    trackingEngine = AyahTrackingEngine();
  });

  tearDown(() async {
    await db.close();
    await fakePlayer.dispose();
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('QA.6 Phase 6.8: Full Quran Download End-to-End Runtime Integration Tests', () {
    test('1. Full Sequential Queue Lifecycle: Verified-Skipped -> Sequential Download -> Atomic Promotion -> Cubit Reflection', () async {
      // Step A: Pre-seed Surah 1 & 2 as verified completed in local storage
      final preseedAudioBytes = List.generate(512, (i) => (i * 3 + 7) % 256);
      final preseedSha256 = sha256.convert(preseedAudioBytes).toString();

      for (int surahNum = 1; surahNum <= 2; surahNum++) {
        final destFile = await storageService.resolveSurahFile(surahNum, '7');
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(preseedAudioBytes, flush: true);

        await localDataSource.saveDownloadRecord(AudioDownloadModel(
          surahNumber: surahNum,
          reciterId: '7',
          localRelativePath: 'reciter_7/surah_$surahNum.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: preseedAudioBytes.length,
          sha256: preseedSha256,
          transferIntegrityVerified: true,
          downloadedAt: DateTime.now(),
        ));
      }

      // Step B: Set up Mock HTTP Client for remaining Surahs (3..114)
      final fakeTrackBytes = List.generate(512, (i) => (i * 5 + 11) % 256);
      final trackSha256 = sha256.convert(fakeTrackBytes).toString();
      final downloadedSurahTracker = <int>[];

      final mockHttpClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'content-length': '${fakeTrackBytes.length}',
              'accept-ranges': 'bytes',
              'etag': '"$trackSha256"',
            },
          );
        }
        if (request.method == 'GET') {
          final uriParts = request.url.pathSegments;
          final fileName = uriParts.last;
          final surahNum = int.tryParse(fileName.replaceAll('.mp3', '')) ?? 0;
          downloadedSurahTracker.add(surahNum);

          return http.StreamedResponse(
            Stream.value(fakeTrackBytes),
            200,
            headers: {
              'content-length': '${fakeTrackBytes.length}',
              'content-type': 'audio/mpeg',
              'etag': '"$trackSha256"',
            },
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockHttpClient,
        coordinator: coordinator,
      );

      final queueService = QuranAudioQueueService(
        queueRepository: queueRepo,
        downloadService: downloadService,
        localDataSource: localDataSource,
        storageService: storageService,
        coordinator: coordinator,
      );

      final cubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeQuranRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeQuranRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeQuranRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeQuranRepo),
        trackingEngine: trackingEngine,
        audioHandler: handler,
        downloadService: downloadService,
        downloadRepository: downloadRepo,
        queueService: queueService,
      );

      await cubit.init();

      // Step C: Verify initial state
      expect(cubit.state.isFullQuranDownloaded, isFalse);
      expect(cubit.state.downloadedReciterIds.contains('7'), isFalse);

      // Step D: Start full Quran queue for reciter '7'
      final completer = Completer<void>();
      final progressList = <QuranDownloadQueueProgress>[];
      final progressSub = queueService.progressStream.listen((p) {
        progressList.add(p);
        if (p.isCompleted && !completer.isCompleted) {
          completer.complete();
        }
      });

      await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (surah) => 'https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/$surah.mp3',
        expectedSurahSizes: List.filled(114, fakeTrackBytes.length),
      );

      await completer.future.timeout(const Duration(seconds: 15));
      await progressSub.cancel();

      // Step E: Verify verified-skipped pre-check
      // Surahs 1 and 2 were NOT fetched over the network
      expect(downloadedSurahTracker.contains(1), isFalse);
      expect(downloadedSurahTracker.contains(2), isFalse);
      // Surahs 3..114 were downloaded sequentially
      expect(downloadedSurahTracker.contains(3), isTrue);
      expect(downloadedSurahTracker.contains(114), isTrue);
      expect(downloadedSurahTracker.length, equals(112));

      // Step F: Verify queue items in SQLite
      final activeQueueResult = await queueRepo.getActiveQueue();
      // Completed queue is no longer active
      expect(activeQueueResult.getOrElse(() => null), isNull);

      final allRecords = await downloadRepo.getAllDownloadedRecords();
      final reciter7Records = allRecords.where((r) => r.reciterId == '7').toList();
      expect(reciter7Records.length, equals(114));

      // Step G: Verify Cubit reflectively knows all 114 Surahs are downloaded
      await cubit.checkAllDownloadedReciters();
      expect(cubit.state.isFullQuranDownloaded, isTrue);
      expect(cubit.state.downloadedReciterIds.contains('7'), isTrue);

      downloadService.dispose();
      queueService.dispose();
      await cubit.close();
    });

    test('2. Storage Preflight & Floor Guard (AC-7): Rejects queue when available space < required + 25MB floor', () async {
      final mockHttpClient = MockClient((_) async => http.Response('', 404));
      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockHttpClient,
        coordinator: coordinator,
      );

      final preflightStorageService = QuranAudioStorageService(
        customBaseDirectoryProvider: () => testDir,
        customDiskSpaceProvider: () async => 30 * 1024 * 1024, // 30 MB available
      );

      final queueService = QuranAudioQueueService(
        queueRepository: queueRepo,
        downloadService: downloadService,
        localDataSource: localDataSource,
        storageService: preflightStorageService,
        coordinator: coordinator,
      );

      // 114 Surahs each of 1 MB = 114 MB required + 25 MB floor = 139 MB required > 30 MB available
      final preflight = await queueService.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: List.filled(114, 1024 * 1024),
      );

      expect(preflight.isInsufficient, isTrue);
      expect(preflight.isSufficient, isFalse);
      expect(preflight.isIndeterminate, isFalse);
      expect(preflight.requiredBytes, equals((114 + 25) * 1024 * 1024));
      expect(preflight.availableBytes, equals(30 * 1024 * 1024));

      // Indeterminate test: null size triggers indeterminate
      final indeterminatePreflight = await queueService.checkStoragePreflight(
        reciterId: '7',
        expectedSurahSizes: [null, ...List.filled(113, 1024 * 1024)],
      );
      expect(indeterminatePreflight.isIndeterminate, isTrue);

      downloadService.dispose();
      queueService.dispose();
    });

    test('3. Queue Operations (Pause, Resume, Concurrency Lock): Coordinates ticket and transitions states', () async {
      final fakeDownloadService = _ControllableFakeDownloadService();
      fakeDownloadService.downloadDelayMs = 25;

      final queueService = QuranAudioQueueService(
        queueRepository: queueRepo,
        downloadService: fakeDownloadService,
        localDataSource: localDataSource,
        storageService: storageService,
        coordinator: coordinator,
      );

      final queue = await queueService.startQueue(
        reciterId: '7',
        urlBuilder: (s) => 'https://example.com/$s.mp3',
        expectedSurahSizes: List.filled(114, 500),
      );

      // Wait brief moment for worker to begin processing
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final activeBeforePause = await queueRepo.getActiveQueue();
      expect(activeBeforePause.getOrElse(() => null), isNotNull);

      // Pause queue
      await queueService.pauseQueue(queue.id);
      expect(queueService.currentProgress?.status, equals(QuranDownloadQueueStatus.paused));

      // Mutual exclusion test: coordinator ticket was released, single download can now reserve
      final singleTicket = await coordinator.reserveSingleSurah(surahNumber: 5, reciterId: '7');
      expect(singleTicket, isNotNull);
      singleTicket.dispose();

      // Resume queue
      fakeDownloadService.isPaused = false;
      fakeDownloadService.downloadDelayMs = 0; // resume at max speed

      final completer = Completer<void>();
      final sub = queueService.progressStream.listen((p) {
        if (p.isCompleted && !completer.isCompleted) {
          completer.complete();
        }
      });

      await queueService.resumeQueue(
        queueId: queue.id,
        urlBuilder: (s) => 'https://example.com/$s.mp3',
      );

      await completer.future.timeout(const Duration(seconds: 10));
      await sub.cancel();
      expect(queueService.currentProgress?.status, equals(QuranDownloadQueueStatus.completed));

      fakeDownloadService.dispose();
      queueService.dispose();
    });

    test('4. Crash Recovery on App Startup (Rev 7 §2.3 Matrix): Normalizes running queue to paused', () async {
      // Seed a simulated interrupted queue directly in SQLite repository
      final now = DateTime.now();
      const crashedQueueId = 'queue_crashed_test_123';

      final initialItems = List.generate(114, (i) {
        final surah = i + 1;
        if (surah <= 15) {
          return QuranDownloadQueueItem(
            id: 'item_$surah',
            queueId: crashedQueueId,
            surahNumber: surah,
            position: i,
            status: QuranDownloadQueueItemStatus.completed,
            downloadedBytes: 1000,
            expectedBytes: 1000,
            attemptCount: 1,
            createdAt: now,
            updatedAt: now,
          );
        } else if (surah == 16) {
          return QuranDownloadQueueItem(
            id: 'item_16',
            queueId: crashedQueueId,
            surahNumber: 16,
            position: i,
            status: QuranDownloadQueueItemStatus.running,
            downloadedBytes: 500,
            expectedBytes: 1000,
            attemptCount: 1,
            createdAt: now,
            updatedAt: now,
          );
        } else {
          return QuranDownloadQueueItem(
            id: 'item_$surah',
            queueId: crashedQueueId,
            surahNumber: surah,
            position: i,
            status: QuranDownloadQueueItemStatus.pending,
            downloadedBytes: 0,
            expectedBytes: 1000,
            attemptCount: 0,
            createdAt: now,
            updatedAt: now,
          );
        }
      });

      final queue = QuranDownloadQueue(
        id: crashedQueueId,
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: 15,
        downloadedBytes: 15000,
        createdAt: now,
        updatedAt: now,
        items: initialItems,
      );
      await queueRepo.createQueue(queue);

      final mockHttpClient = MockClient((_) async => http.Response('', 404));
      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockHttpClient,
        coordinator: coordinator,
      );

      final queueService = QuranAudioQueueService(
        queueRepository: queueRepo,
        downloadService: downloadService,
        localDataSource: localDataSource,
        storageService: storageService,
        coordinator: coordinator,
      );

      // Perform recovery on startup
      await queueService.recoverInterruptedQueuesOnStartup();

      // Queue status must be normalized to paused
      final recoveredQueue = (await queueRepo.getActiveQueue()).getOrElse(() => null);
      expect(recoveredQueue, isNotNull);
      expect(recoveredQueue!.status, equals(QuranDownloadQueueStatus.paused));

      // Running item must be normalized to paused
      final items = (await queueRepo.getQueueItems(crashedQueueId)).getOrElse(() => []);
      final recoveredItem16 = items.firstWhere((i) => i.surahNumber == 16);
      expect(recoveredItem16.status, equals(QuranDownloadQueueItemStatus.paused));

      downloadService.dispose();
      queueService.dispose();
    });
  });
}
