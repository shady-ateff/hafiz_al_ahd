import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_quran_audio_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_reciters_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_surah_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/save_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_cubit.dart';

class FakeQuranAudioRepository implements BaseQuranAudioRepository {
  List<AudioReciter> reciters = [];
  Map<int, SurahAudio> surahMap = {};
  PlaybackPosition? savedPosition;
  int savePositionCallCount = 0;
  QuranAudioFailure? failureToReturn;

  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({
    bool forceRefresh = false,
  }) async {
    if (failureToReturn != null) return Left(failureToReturn!);
    return Right(reciters);
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (failureToReturn != null) return Left(failureToReturn!);
    if (surahMap.containsKey(surahNumber)) return Right(surahMap[surahNumber]!);
    return Left(QuranAudioNotFoundFailure(message: 'Not found'));
  }

  @override
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter() async {
    if (reciters.isNotEmpty) return Right(reciters.first);
    return Left(QuranAudioNotFoundFailure(message: 'No reciter'));
  }

  @override
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId) async {
    return const Right(null);
  }

  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (surahMap.containsKey(surahNumber)) return Right(surahMap[surahNumber]!.ayahTimings);
    return const Right([]);
  }

  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async {
    return Right(savedPosition);
  }

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async {
    savedPosition = position;
    savePositionCallCount++;
    return const Right(null);
  }
}

class FakeTestQuranAudioPlayer implements QuranAudioPlayer {
  final StreamController<QuranPlaybackStatus> statusController =
      StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> posController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> durController =
      StreamController<Duration?>.broadcast();

  QuranPlaybackStatus currentStatus = QuranPlaybackStatus.idle;
  Duration currentPos = Duration.zero;
  Duration? currentDur;
  SurahAudio? loadedTrack;
  String? loadedLocalPath;
  AudioRepeatMode currentRepeatMode = AudioRepeatMode.continuous;
  int? currentRepeatCount;
  bool playCalled = false;
  bool pauseCalled = false;
  bool stopCalled = false;
  bool isDisposed = false;
  Duration? lastSeekPos;
  double volume = 1.0;

  @override
  Stream<QuranPlaybackStatus> get playbackStatusStream => statusController.stream;

  @override
  Stream<Duration> get positionStream => posController.stream;

  @override
  Stream<Duration?> get durationStream => durController.stream;

  @override
  QuranPlaybackStatus get status => currentStatus;

  @override
  bool get isPlaying => currentStatus == QuranPlaybackStatus.playing;

  @override
  Duration get currentPosition => currentPos;

  @override
  Duration? get duration => currentDur;

  @override
  SurahAudio? get currentTrack => loadedTrack;

  @override
  AudioRepeatMode get repeatMode => currentRepeatMode;

  @override
  int? get repeatCount => currentRepeatCount;

  @override
  Future<void> loadSurah({
    required SurahAudio surahAudio,
    String? localFilePath,
    Duration? startPosition,
  }) async {
    loadedTrack = surahAudio;
    loadedLocalPath = localFilePath;
    currentDur = Duration(milliseconds: surahAudio.durationMs);
    durController.add(currentDur);
    currentPos = startPosition ?? Duration.zero;
    posController.add(currentPos);
    currentStatus = QuranPlaybackStatus.paused;
    statusController.add(currentStatus);
  }

  @override
  Future<void> play() async {
    playCalled = true;
    currentStatus = QuranPlaybackStatus.playing;
    statusController.add(currentStatus);
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    currentStatus = QuranPlaybackStatus.paused;
    statusController.add(currentStatus);
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    currentStatus = QuranPlaybackStatus.idle;
    statusController.add(currentStatus);
  }

  @override
  Future<void> seekTo(Duration position) async {
    lastSeekPos = position;
    currentPos = position;
    posController.add(position);
  }

  @override
  Future<void> setVolume(double newVolume) async {
    volume = newVolume;
  }

  @override
  Future<void> setRepeatMode(
    AudioRepeatMode mode, {
    int? rangeStartAyah,
    int? rangeEndAyah,
    int? repeatCount,
  }) async {
    currentRepeatMode = mode;
    currentRepeatCount = repeatCount;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await statusController.close();
    await posController.close();
    await durController.close();
  }

  void emitStatus(QuranPlaybackStatus s) {
    currentStatus = s;
    statusController.add(s);
  }

  void emitPosition(Duration p) {
    currentPos = p;
    posController.add(p);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuranAudioCubit Playback & State Management', () {
    late FakeQuranAudioRepository audioRepo;
    late FakeTestQuranAudioPlayer player;
    late QuranAudioHandler handler;
    late AyahTrackingEngine trackingEngine;
    late QuranAudioCubit cubit;

    final testReciters = [
      AudioReciter(
        id: '7',
        name: 'Mishari Rashid al-`Afasy',
        arabicName: 'مشاري راشد العفاسي',
        style: 'Murattal',
      ),
      AudioReciter(
        id: '1',
        name: 'AbdulBaset AbdulSamad',
        arabicName: 'عبد الباسط عبد الصمد',
        style: 'Mujawwad',
      ),
    ];

    final testSurahAudio1 = SurahAudio(
      surahNumber: 1,
      reciterId: '7',
      audioUrl: 'https://cdn.example.com/audio/001.mp3',
      format: 'mp3',
      durationMs: 46000,
      ayahTimings: [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5000, timestampTo: 10000),
        AyahTiming(surahNumber: 1, ayahNumber: 3, timestampFrom: 10000, timestampTo: 15000),
      ],
    );

    final testSurahAudio2 = SurahAudio(
      surahNumber: 2,
      reciterId: '7',
      audioUrl: 'https://cdn.example.com/audio/002.mp3',
      format: 'mp3',
      durationMs: 120000,
      ayahTimings: [
        AyahTiming(surahNumber: 2, ayahNumber: 1, timestampFrom: 0, timestampTo: 6000),
        AyahTiming(surahNumber: 2, ayahNumber: 6, timestampFrom: 40000, timestampTo: 50000),
      ],
    );

    setUp(() {
      audioRepo = FakeQuranAudioRepository();
      player = FakeTestQuranAudioPlayer();
      trackingEngine = AyahTrackingEngine();

      audioRepo.reciters = testReciters;
      audioRepo.surahMap[1] = testSurahAudio1;
      audioRepo.surahMap[2] = testSurahAudio2;

      handler = QuranAudioHandler(
        player: player,
        getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
      );

      cubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(audioRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
        audioHandler: handler,
        trackingEngine: trackingEngine,
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
      );
    });

    tearDown(() async {
      await cubit.close();
      await handler.disposeHandler();
      await player.dispose();
    });

    test('initial state has canonical reciters and default idle values', () {
      expect(cubit.state.reciters, isNotEmpty);
      expect(cubit.state.selectedReciter?.id, '7');
      expect(cubit.state.currentSurahNumber, isNull);
      expect(cubit.state.isPlaying, isFalse);
      expect(cubit.state.isLocal, isFalse);
    });

    test('init loads reciters and selects default reciter Mishari Alafasy', () async {
      await cubit.init();

      expect(cubit.state.reciters.length, 2);
      expect(cubit.state.selectedReciter?.id, '7');
      expect(cubit.state.selectedReciter?.arabicName, 'مشاري راشد العفاسي');
    });

    test('selectReciter changes selected reciter and resets tracking', () async {
      await cubit.init();

      cubit.selectReciter('1');
      expect(cubit.state.selectedReciter?.id, '1');
      expect(cubit.state.selectedReciter?.arabicName, 'عبد الباسط عبد الصمد');
      expect(cubit.state.highlightState.activeAyah, isNull);
    });

    test('playSurah strictly streams from remote without invoking download workflows', () async {
      await cubit.init();

      await cubit.playSurah(surahNumber: 1);

      expect(cubit.state.isLoadingAudio, isFalse);
      expect(cubit.state.currentSurahNumber, 1);
      expect(cubit.state.isLocal, isFalse);
      expect(player.loadedTrack?.surahNumber, 1);
      expect(player.loadedLocalPath, isNull); // Online streaming
      expect(player.playCalled, isTrue);
    });

    test('playSurah handles network failure gracefully', () async {
      await cubit.init();

      audioRepo.failureToReturn = QuranAudioNetworkFailure(message: 'No internet connection');

      await cubit.playSurah(surahNumber: 1);

      expect(cubit.state.isLoadingAudio, isFalse);
      expect(cubit.state.playbackStatus, QuranPlaybackStatus.error);
      expect(cubit.state.errorMessage, 'No internet connection');
      expect(cubit.state.isOfflineError, isTrue);
    });

    test('position updates trigger Ayah tracking highlight without affecting manual selection', () async {
      await cubit.init();
      await cubit.playSurah(surahNumber: 1);

      // Ayah 1 is 0..5000ms
      player.posController.add(const Duration(milliseconds: 2500));
      await pumpEventQueue();

      expect(cubit.state.highlightState.activeAyah?.ayahNumber, 1);
      expect(cubit.state.highlightState.activeAyah?.surahNumber, 1);

      // Ayah 2 is 5000..10000ms
      player.posController.add(const Duration(milliseconds: 7000));
      await pumpEventQueue();

      expect(cubit.state.highlightState.activeAyah?.ayahNumber, 2);
    });

    test('seekToAyah seeks player to Ayah start timestamp', () async {
      await cubit.init();
      await cubit.playSurah(surahNumber: 1);

      await cubit.seekToAyah(3); // Ayah 3 starts at 10000ms

      expect(player.lastSeekPos, const Duration(milliseconds: 10000));
    });

    test('pause, resume, and stop invoke player and update state', () async {
      await cubit.init();
      await cubit.playSurah(surahNumber: 1);

      await cubit.pause();
      expect(player.pauseCalled, isTrue);

      await cubit.resume();
      expect(player.playCalled, isTrue);

      await cubit.stop();
      expect(player.stopCalled, isTrue);
      expect(cubit.state.highlightState.activeAyah, isNull);
    });

    test('repeatMode updates player and highlight state', () async {
      await cubit.init();
      await cubit.playSurah(surahNumber: 1);

      await cubit.setRepeatMode(
        AudioRepeatMode.singleAyah,
        rangeStartAyah: 2,
      );

      expect(player.currentRepeatMode, AudioRepeatMode.singleAyah);
      expect(cubit.state.highlightState.repeatMode, AudioRepeatMode.singleAyah);
      expect(cubit.state.highlightState.repeatRangeStart?.ayahNumber, 2);
    });

    group('Player Lifecycle & DI Safety (P1)', () {
      test('Cubit.close() DOES NOT dispose shared QuranAudioPlayer singleton', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        // When user navigates away from the screen, QuranAudioCubit is closed
        await cubit.close();

        // Architectural Guarantee: The singleton player MUST remain alive
        expect(player.isDisposed, isFalse);

        // When a new Cubit is instantiated (e.g. user returns to Quran screen)
        final cubitB = QuranAudioCubit(
          getRecitersUseCase: GetRecitersUseCase(audioRepo),
          getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
          audioHandler: handler,
          trackingEngine: trackingEngine,
          savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
          getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
        );

        // Cubit B can observe and interact with player seamlessly
        expect(player.isDisposed, isFalse);
        await cubitB.close();
        expect(player.isDisposed, isFalse);
      });
    });

    group('Position Persistence & Restoration Full Coverage (P1)', () {
      test('persists playback position on pause', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        player.posController.add(const Duration(milliseconds: 8000));
        await pumpEventQueue();

        await cubit.pause();

        expect(audioRepo.savedPosition, isNotNull);
        expect(audioRepo.savedPosition?.surahNumber, 1);
        expect(audioRepo.savedPosition?.reciterId, '7');
        expect(audioRepo.savedPosition?.positionMs, 8000);
        expect(audioRepo.savedPosition?.currentAyahNumber, 2);
      });

      test('persists playback position on stop', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        player.posController.add(const Duration(milliseconds: 4000));
        await pumpEventQueue();

        await cubit.stop();

        expect(audioRepo.savedPosition, isNotNull);
        expect(audioRepo.savedPosition?.surahNumber, 1);
        expect(audioRepo.savedPosition?.currentAyahNumber, 1);
      });

      test('persists playback position on completed', () async {
        await cubit.init();
        await cubit.setRepeatMode(AudioRepeatMode.off);
        await cubit.playSurah(surahNumber: 1);

        // Simulate playback completion event
        player.statusController.add(QuranPlaybackStatus.completed);
        await pumpEventQueue();

        expect(audioRepo.savedPosition, isNotNull);
        expect(cubit.state.playbackStatus, QuranPlaybackStatus.idle);
        expect(cubit.state.currentPosition, Duration.zero);
        expect(cubit.state.highlightState.activeAyah, isNull);
      });

      test('auto-advances to next Surah when track completes in AudioRepeatMode.continuous', () async {
        await cubit.init();
        expect(cubit.state.highlightState.repeatMode, AudioRepeatMode.continuous);
        await cubit.playSurah(surahNumber: 1);

        player.statusController.add(QuranPlaybackStatus.completed);
        await pumpEventQueue();

        expect(audioRepo.savedPosition, isNotNull);
        expect(cubit.state.playbackStatus, anyOf(QuranPlaybackStatus.loading, QuranPlaybackStatus.playing));
      });

      test('stops cleanly when Surah 114 completes in AudioRepeatMode.continuous', () async {
        await cubit.init();
        expect(cubit.state.highlightState.repeatMode, AudioRepeatMode.continuous);
        await cubit.playSurah(surahNumber: 114);

        player.statusController.add(QuranPlaybackStatus.completed);
        await pumpEventQueue();

        expect(audioRepo.savedPosition, isNotNull);
        expect(cubit.state.playbackStatus, QuranPlaybackStatus.idle);
        expect(cubit.state.currentPosition, Duration.zero);
        expect(cubit.state.highlightState.isPlaying, isFalse);
      });

      test('persists playback position on Cubit.close()', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        player.posController.add(const Duration(milliseconds: 6500));
        await pumpEventQueue();

        final initialCount = audioRepo.savePositionCallCount;
        await cubit.close();

        expect(audioRepo.savePositionCallCount, initialCount + 1);
        expect(audioRepo.savedPosition?.positionMs, 6500);
      });

      test('restores saved position and active Ayah on init() without auto-playing', () async {
        audioRepo.savedPosition = PlaybackPosition(
          reciterId: '7',
          surahNumber: 1,
          positionMs: 6000,
          currentAyahNumber: 2,
          durationMs: 46000,
        );

        await cubit.init();

        expect(cubit.state.currentSurahNumber, 1);
        expect(cubit.state.currentPosition, const Duration(milliseconds: 6000));
        expect(cubit.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 2));
        expect(cubit.state.isPlaying, isFalse);
        expect(player.playCalled, isFalse);
      });
    });

    group('AudioHandler Integration (QA.3)', () {
      test('playSurah updates AudioHandler mediaItem with Surah title and reciter', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        final item = handler.mediaItem.value;
        expect(item, isNotNull);
        expect(item!.id, 'surah_1');
        expect(item.title, 'سورة الفاتحة');
        expect(item.artist, 'مشاري راشد العفاسي');
        expect(item.album, 'القرآن الكريم');
      });

      test('external skipToNext from lock screen triggers next Surah playback', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);

        // User taps "Next" on lockscreen or Bluetooth headset
        await handler.skipToNext();
        await pumpEventQueue();

        expect(cubit.state.currentSurahNumber, 2);
        expect(handler.mediaItem.value?.title, 'سورة البقرة');
      });

      test('external skipToPrevious from lock screen triggers previous Surah playback', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 2);

        // User taps "Previous" on lockscreen or Bluetooth headset
        await handler.skipToPrevious();
        await pumpEventQueue();

        expect(cubit.state.currentSurahNumber, 1);
        expect(handler.mediaItem.value?.title, 'سورة الفاتحة');
      });

      test('DEFECT-FIX: playNextSurah updates currentSurah, retains playing state, and togglePlayPause pauses immediately', () async {
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);
        player.currentStatus = QuranPlaybackStatus.playing;
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();

        expect(cubit.state.isPlaying, isTrue);
        expect(cubit.state.currentSurahNumber, 1);

        // User advances to next Surah (Surah 2)
        await cubit.playNextSurah();
        player.currentStatus = QuranPlaybackStatus.playing;
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();

        // 1. Surah number and track updated
        expect(cubit.state.currentSurahNumber, 2);
        expect(cubit.state.isPlaying, isTrue);

        // 2. Tapping togglePlayPause must immediately PAUSE without requiring stop
        await cubit.togglePlayPause();
        await pumpEventQueue();

        expect(player.pauseCalled, isTrue);
      });

      test('Cubit Reconnection (E): Newly instantiated Cubit B immediately restores track, position and Ayah highlight from background handler', () async {
        // 1. Cubit A initiates playback of Surah 1
        await cubit.init();
        await cubit.playSurah(surahNumber: 1);
        player.currentStatus = QuranPlaybackStatus.playing;
        player.emitStatus(QuranPlaybackStatus.playing);

        // 2. User leaves Quran screen -> Cubit A closes
        await cubit.close();

        // 3. Audio continues playing in background via AudioHandler; position reaches 7000ms (Ayah 2)
        player.currentPos = const Duration(milliseconds: 7000);
        player.emitPosition(const Duration(milliseconds: 7000));
        await pumpEventQueue();

        // 4. User re-opens Quran screen -> Cubit B is created
        final cubitB = QuranAudioCubit(
          getRecitersUseCase: GetRecitersUseCase(audioRepo),
          getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
          audioHandler: handler,
          trackingEngine: AyahTrackingEngine(),
          savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
          getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
        );

        // 5. Verification: Cubit B immediately has track, position, playing status, and active Ayah
        expect(cubitB.state.currentSurahNumber, 1);
        expect(cubitB.state.currentPosition, const Duration(milliseconds: 7000));
        expect(cubitB.state.playbackStatus, QuranPlaybackStatus.playing);
        expect(cubitB.state.highlightState.isPlaying, isTrue);
        expect(cubitB.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 2));

        // 6. Calling init() preserves ongoing playback without resetting to old database state
        await cubitB.init();
        expect(cubitB.state.currentSurahNumber, 1);
        expect(cubitB.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 2));

        await cubitB.close();
      });

      test('QA3-FV-05: Full 9-step Cubit Disconnect & Reconnect Lifecycle Verification', () async {
        // Step 1: Create Cubit A
        final cubitA = QuranAudioCubit(
          getRecitersUseCase: GetRecitersUseCase(audioRepo),
          getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
          audioHandler: handler,
          trackingEngine: AyahTrackingEngine(),
          savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
          getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
        );
        await cubitA.init();

        // Step 2: Play Surah 1
        await cubitA.playSurah(surahNumber: 1);
        player.currentStatus = QuranPlaybackStatus.playing;
        player.emitStatus(QuranPlaybackStatus.playing);

        // Step 3: Advance audio to 3000ms (Ayah 1)
        player.currentPos = const Duration(milliseconds: 3000);
        player.emitPosition(const Duration(milliseconds: 3000));
        await pumpEventQueue();
        expect(cubitA.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 1));

        // Step 4: Close Cubit A (user leaves Quran screen)
        await cubitA.close();

        // Step 5: Audio continues in background for 10 seconds -> advances to 7000ms (Ayah 2)
        player.currentPos = const Duration(milliseconds: 7000);
        player.emitPosition(const Duration(milliseconds: 7000));
        await pumpEventQueue();

        // Step 6: Create Cubit B (user returns to Quran screen)
        final cubitB = QuranAudioCubit(
          getRecitersUseCase: GetRecitersUseCase(audioRepo),
          getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
          audioHandler: handler,
          trackingEngine: AyahTrackingEngine(),
          savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
          getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
        );

        // Step 7: Verify Cubit B snapshot immediately:
        // - same Surah
        // - same Reciter
        // - modern position (7000ms, NOT old 3000ms)
        // - correct PlaybackStatus (playing)
        // - Ayah Highlight matches current position (Ayah 2)
        expect(cubitB.state.currentSurahNumber, 1);
        expect(cubitB.state.selectedReciter?.id, '7');
        expect(cubitB.state.currentPosition, const Duration(milliseconds: 7000));
        expect(cubitB.state.playbackStatus, QuranPlaybackStatus.playing);
        expect(cubitB.state.highlightState.isPlaying, isTrue);
        expect(cubitB.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 2));

        // Step 8: Advance position AFTER Cubit B is created to 12000ms (Ayah 3)
        player.currentPos = const Duration(milliseconds: 12000);
        player.emitPosition(const Duration(milliseconds: 12000));
        await pumpEventQueue();

        // Step 9: Verify highlight and state update continuously in Cubit B without recreating Cubit
        expect(cubitB.state.currentPosition, const Duration(milliseconds: 12000));
        expect(cubitB.state.highlightState.activeAyah, AyahId(surahNumber: 1, ayahNumber: 3));

        await cubitB.close();
      });

      test('togglePlayPause on first launch with no active track loads and plays fallback or default surah', () async {
        // Fresh launch state: no track loaded, status idle, currentSurahNumber is null
        expect(cubit.state.currentSurahAudio, isNull);
        expect(cubit.state.isPlaying, isFalse);

        await cubit.togglePlayPause(fallbackSurahNumber: 1);
        await pumpEventQueue();

        expect(cubit.state.currentSurahNumber, 1);
        expect(cubit.state.isLoadingAudio, isFalse);
        expect(player.playCalled, isTrue);
      });

      test('togglePlayPause when playing calls pause', () async {
        await cubit.playSurah(surahNumber: 1);
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();
        expect(cubit.state.isPlaying, isTrue);

        await cubit.togglePlayPause();
        await pumpEventQueue();

        expect(player.pauseCalled, isTrue);
      });

      test('togglePlayPause when paused resumes existing playback without reload', () async {
        await cubit.playSurah(surahNumber: 1);
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();

        await cubit.pause();
        player.emitStatus(QuranPlaybackStatus.paused);
        await pumpEventQueue();
        expect(cubit.state.isPaused, isTrue);

        player.playCalled = false;
        await cubit.togglePlayPause();
        await pumpEventQueue();

        expect(player.playCalled, isTrue);
      });

      // --- Page-Aware Surah Resolver Tests (QA.4 Rev 2) ---
      test('Page-Aware Surah Resolver Case 1 & 2: first play on page resolves fallbackSurahNumber', () async {
        // Initially no active track
        expect(cubit.state.currentSurahAudio, isNull);

        // User is viewing Surah 2 (e.g. Page 20) and taps play
        await cubit.togglePlayPause(fallbackSurahNumber: 2);
        await pumpEventQueue();

        expect(cubit.state.currentSurahNumber, 2);
        expect(player.playCalled, isTrue);
      });

      test('Page-Aware Surah Resolver Case 3: active track is NOT overridden by fallbackSurahNumber', () async {
        // Start playback on Surah 1
        await cubit.playSurah(surahNumber: 1);
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();
        expect(cubit.state.currentSurahNumber, 1);
        expect(cubit.state.isPlaying, isTrue);

        // User navigates Mushaf pages to Surah 2, and taps togglePlayPause
        player.pauseCalled = false;
        await cubit.togglePlayPause(fallbackSurahNumber: 2);
        await pumpEventQueue();

        // Must pause existing Surah 1 without switching to Surah 2
        expect(cubit.state.currentSurahNumber, 1);
        expect(player.pauseCalled, isTrue);
      });

      test('QA3-FV-01: Concurrent init calls return exact same in-flight Future', () async {
        final f1 = cubit.init();
        final f2 = cubit.init();

        expect(identical(f1, f2), isTrue);

        await Future.wait([f1, f2]);
        expect(cubit.state.reciters.length, 2);
      });

      test('QA4-R3-01: Stop clears active audio and allows subsequent play to start new page Surah', () async {
        // 1. Start playback of Surah 1
        await cubit.playSurah(surahNumber: 1);
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();
        expect(cubit.state.currentSurahNumber, 1);
        expect(cubit.state.isPlaying, isTrue);

        // 2. Stop playback
        await cubit.stop();
        await pumpEventQueue();
        expect(cubit.state.playbackStatus, QuranPlaybackStatus.idle);
        expect(cubit.state.currentSurahAudio, isNull);
        expect(cubit.state.currentSurahNumber, isNull);

        // 3. User navigates to Page 20 (Surah 2) and taps play
        player.playCalled = false;
        await cubit.togglePlayPause(fallbackSurahNumber: 2);
        await pumpEventQueue();

        // 4. Verify Surah 2 is loaded and played (NOT the old Surah 1)
        expect(cubit.state.currentSurahNumber, 2);
        expect(player.playCalled, isTrue);
      });

      test('Page-Aware Start: togglePlayPause starts playback directly at fallbackStartAyahNumber when idle', () async {
        // Given player is idle
        expect(cubit.state.playbackStatus, QuranPlaybackStatus.idle);

        // When user is on a page where Surah 2 starts at Ayah 6 (e.g. Page 3)
        await cubit.togglePlayPause(
          fallbackSurahNumber: 2,
          fallbackStartAyahNumber: 6,
        );
        await pumpEventQueue();

        // Then Surah 2 is loaded and started at Ayah 6's timestamp (40000ms)
        expect(cubit.state.currentSurahNumber, 2);
        expect(player.currentPos, const Duration(milliseconds: 40000));
        expect(player.playCalled, isTrue);
      });

      test('Self-Healing: _handlePositionUpdate locks playing state if audio is actively advancing', () async {
        await cubit.playSurah(surahNumber: 1);
        player.currentStatus = QuranPlaybackStatus.playing;
        player.emitStatus(QuranPlaybackStatus.playing);
        await pumpEventQueue();

        // Simulate a momentary status de-sync (e.g. from buffering or network race)
        cubit.emit(cubit.state.copyWith(playbackStatus: QuranPlaybackStatus.buffering));
        expect(cubit.state.isPlaying, isFalse);

        // Active position tick arrives from audioHandler
        player.emitPosition(const Duration(milliseconds: 1500));
        await pumpEventQueue();

        // Self-healing synchronization must restore playing state immediately
        expect(cubit.state.isPlaying, isTrue);
        expect(cubit.state.playbackStatus, QuranPlaybackStatus.playing);
      });
    });
  });
}
