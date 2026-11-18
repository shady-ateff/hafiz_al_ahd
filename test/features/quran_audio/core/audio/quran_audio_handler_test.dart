import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_service_initializer.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_quran_audio_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_surah_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/save_playback_position_use_case.dart';

class FakeQuranAudioPlayerForHandler implements QuranAudioPlayer {
  final StreamController<QuranPlaybackStatus> statusController =
      StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> posController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> durController =
      StreamController<Duration?>.broadcast();

  QuranPlaybackStatus currentStatus = QuranPlaybackStatus.idle;
  Duration currentPos = Duration.zero;
  Duration? currentDur;
  SurahAudio? currentTrackAudio;
  bool playCalled = false;
  bool pauseCalled = false;
  bool stopCalled = false;
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
  Duration get currentPosition => currentPos;

  @override
  Duration? get duration => currentDur;

  @override
  SurahAudio? get currentTrack => currentTrackAudio;

  @override
  AudioRepeatMode get repeatMode => AudioRepeatMode.off;

  @override
  Future<void> loadSurah({
    required SurahAudio surahAudio,
    String? localFilePath,
    Duration? startPosition,
  }) async {
    currentTrackAudio = surahAudio;
    currentDur = Duration(milliseconds: surahAudio.durationMs);
    durController.add(currentDur);
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
  }) async {}

  @override
  Future<void> dispose() async {
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

class FakeAudioSessionForHandler implements AudioSession {
  final StreamController<AudioInterruptionEvent> interruptionController =
      StreamController<AudioInterruptionEvent>.broadcast();
  final StreamController<void> noisyController =
      StreamController<void>.broadcast();

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptionController.stream;

  @override
  Stream<void> get becomingNoisyEventStream => noisyController.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void emitInterruption(AudioInterruptionEvent event) {
    interruptionController.add(event);
  }

  void emitBecomingNoisy() {
    noisyController.add(null);
  }

  Future<void> dispose() async {
    await interruptionController.close();
    await noisyController.close();
  }
}

class FakeRepoForHandler implements BaseQuranAudioRepository {
  final Map<int, SurahAudio> surahs = {};
  PlaybackPosition? lastSavedPos;
  int saveCount = 0;
  bool shouldFailNext = false;
  Future<void> Function(PlaybackPosition)? savePositionCallback;
  Future<Either<QuranAudioFailure, SurahAudio>> Function(int, String)? getSurahAudioCallback;

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (getSurahAudioCallback != null) {
      return await getSurahAudioCallback!(surahNumber, reciterId);
    }
    if (shouldFailNext) {
      return Left(QuranAudioNetworkFailure(message: 'Network error'));
    }
    if (surahs.containsKey(surahNumber)) {
      return Right(surahs[surahNumber]!);
    }
    return Left(QuranAudioNotFoundFailure(message: 'Surah not found'));
  }

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async {
    lastSavedPos = position;
    saveCount++;
    if (savePositionCallback != null) {
      await savePositionCallback!(position);
    }
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSurah1 = SurahAudio(
    surahNumber: 1,
    reciterId: '7',
    audioUrl: 'https://example.com/001.mp3',
    format: 'mp3',
    durationMs: 46000,
    ayahTimings: [
      AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
      AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5000, timestampTo: 10000),
      AyahTiming(surahNumber: 1, ayahNumber: 3, timestampFrom: 10000, timestampTo: 15000),
    ],
  );

  final testSurah2 = SurahAudio(
    surahNumber: 2,
    reciterId: '7',
    audioUrl: 'https://example.com/002.mp3',
    format: 'mp3',
    durationMs: 7200000,
    ayahTimings: [
      AyahTiming(surahNumber: 2, ayahNumber: 1, timestampFrom: 0, timestampTo: 6000),
    ],
  );

  final testSurah114 = SurahAudio(
    surahNumber: 114,
    reciterId: '7',
    audioUrl: 'https://example.com/114.mp3',
    format: 'mp3',
    durationMs: 30000,
    ayahTimings: [
      AyahTiming(surahNumber: 114, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
    ],
  );

  group('QuranAudioHandler (Background Service & Media Notification)', () {
    late FakeQuranAudioPlayerForHandler player;
    late FakeAudioSessionForHandler session;
    late FakeRepoForHandler repo;
    late GetSurahAudioUseCase getSurahAudioUseCase;
    late SavePlaybackPositionUseCase savePlaybackPositionUseCase;
    late QuranAudioHandler handler;

    setUp(() {
      player = FakeQuranAudioPlayerForHandler();
      session = FakeAudioSessionForHandler();
      repo = FakeRepoForHandler();
      repo.surahs[1] = testSurah1;
      repo.surahs[2] = testSurah2;
      repo.surahs[114] = testSurah114;
      getSurahAudioUseCase = GetSurahAudioUseCase(repo);
      savePlaybackPositionUseCase = SavePlaybackPositionUseCase(repo);

      handler = QuranAudioHandler(
        player: player,
        getSurahAudioUseCase: getSurahAudioUseCase,
        savePlaybackPositionUseCase: savePlaybackPositionUseCase,
        audioSession: session,
      );
    });

    tearDown(() async {
      await handler.disposeHandler();
      await player.dispose();
      await session.dispose();
      QuranAudioServiceInitializer.resetForTesting();
    });

    test('initial state broadcasts media controls and system actions', () async {
      final state = handler.playbackState.value;

      expect(state.controls.length, 4);
      expect(state.controls[0], MediaControl.skipToPrevious);
      expect(state.controls[1], MediaControl.play);
      expect(state.controls[2], MediaControl.stop);
      expect(state.controls[3], MediaControl.skipToNext);

      expect(state.systemActions.contains(MediaAction.seek), isTrue);
      expect(state.systemActions.contains(MediaAction.skipToNext), isTrue);
      expect(state.systemActions.contains(MediaAction.skipToPrevious), isTrue);
      expect(state.playing, isFalse);
    });

    test('updateMediaItemForSurah updates MediaItem with canonical Arabic title and reciter', () {
      handler.updateMediaItemForSurah(
        surahNumber: 1,
        reciterName: 'مشاري راشد العفاسي',
        duration: const Duration(seconds: 46),
      );

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.id, 'surah_1');
      expect(item.title, 'سورة الفاتحة');
      expect(item.artist, 'مشاري راشد العفاسي');
      expect(item.album, 'القرآن الكريم');
      expect(item.duration, const Duration(seconds: 46));
      expect(item.extras?['surahNumber'], 1);
    });

    test('updateMediaItemForSurah supports all Surahs canonically (e.g. Al-Baqarah, An-Nas)', () {
      handler.updateMediaItemForSurah(
        surahNumber: 2,
        reciterName: 'عبد الباسط عبد الصمد',
      );
      expect(handler.mediaItem.value?.title, 'سورة البقرة');

      handler.updateMediaItemForSurah(
        surahNumber: 114,
        reciterName: 'عبد الباسط عبد الصمد',
      );
      expect(handler.mediaItem.value?.title, 'سورة الناس');
    });

    test('player status changes update PlaybackState processingState and playing flag', () async {
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
      expect(handler.playbackState.value.controls[1], MediaControl.pause);

      player.emitStatus(QuranPlaybackStatus.paused);
      await pumpEventQueue();

      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
      expect(handler.playbackState.value.controls[1], MediaControl.play);

      player.emitStatus(QuranPlaybackStatus.buffering);
      await pumpEventQueue();
      expect(handler.playbackState.value.processingState, AudioProcessingState.buffering);

      player.emitStatus(QuranPlaybackStatus.completed);
      await pumpEventQueue();
      expect(handler.playbackState.value.processingState, AudioProcessingState.completed);
    });

    test('position updates reflect in PlaybackState updatePosition', () async {
      player.emitPosition(const Duration(seconds: 18));
      await pumpEventQueue();

      expect(handler.playbackState.value.updatePosition, const Duration(seconds: 18));
      expect(handler.playbackState.value.bufferedPosition, const Duration(seconds: 18));
    });

    test('external actions delegate to underlying player', () async {
      await handler.play();
      expect(player.playCalled, isTrue);

      await handler.pause();
      expect(player.pauseCalled, isTrue);

      await handler.seek(const Duration(seconds: 25));
      expect(player.lastSeekPos, const Duration(seconds: 25));

      await handler.stop();
      expect(player.stopCalled, isTrue);
    });

    test('playSurah loads player, broadcasts media item, and begins playback', () async {
      await handler.playSurah(surahAudio: testSurah1, reciterName: 'مشاري راشد العفاسي');

      expect(player.currentTrackAudio, testSurah1);
      expect(player.playCalled, isTrue);
      expect(handler.mediaItem.value?.title, 'سورة الفاتحة');
      expect(handler.currentTrack, testSurah1);
    });

    test('skipToNext and skipToPrevious navigate autonomously via GetSurahAudioUseCase', () async {
      await handler.playSurah(surahAudio: testSurah1, reciterName: 'مشاري راشد العفاسي');

      // User triggers next track from lockscreen
      await handler.skipToNext();
      await pumpEventQueue();

      expect(handler.mediaItem.value?.title, 'سورة البقرة');
      expect(handler.currentTrack?.surahNumber, 2);

      // User triggers previous track from lockscreen
      await handler.skipToPrevious();
      await pumpEventQueue();

      expect(handler.mediaItem.value?.title, 'سورة الفاتحة');
      expect(handler.currentTrack?.surahNumber, 1);
    });

    test('skipToNext at Surah 114 is a safe no-op boundary', () async {
      await handler.playSurah(surahAudio: testSurah114);

      await handler.skipToNext();
      await pumpEventQueue();

      // Should remain at Surah 114
      expect(handler.currentTrack?.surahNumber, 114);
      expect(handler.mediaItem.value?.title, 'سورة الناس');
    });

    test('skipToPrevious at Surah 1 seeks to start of Surah', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.currentPos = const Duration(seconds: 20);

      await handler.skipToPrevious();
      await pumpEventQueue();

      // Remained at Surah 1 and seeked to zero
      expect(handler.currentTrack?.surahNumber, 1);
      expect(player.lastSeekPos, Duration.zero);
    });

    test('failed getSurahAudio keeps existing track and mediaItem intact', () async {
      await handler.playSurah(surahAudio: testSurah1);

      repo.shouldFailNext = true;
      await handler.skipToNext();
      await pumpEventQueue();

      // State preserved without corruption
      expect(handler.currentTrack?.surahNumber, 1);
      expect(handler.mediaItem.value?.title, 'سورة الفاتحة');
    });

    test('Background Position Persistence: persists periodically every 10s during playback', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // Position update within 10s: no write
      player.emitPosition(const Duration(milliseconds: 5000));
      await pumpEventQueue();
      expect(repo.saveCount, 0);

      // Position update reaching 11s: triggers periodic persistence
      player.emitPosition(const Duration(milliseconds: 11000));
      await pumpEventQueue();

      expect(repo.saveCount, 1);
      expect(repo.lastSavedPos?.surahNumber, 1);
      expect(repo.lastSavedPos?.positionMs, 11000);
      expect(repo.lastSavedPos?.currentAyahNumber, 3);
    });

    test('Background Position Persistence: persists on pause, stop, completed, and onTaskRemoved', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.currentPos = const Duration(milliseconds: 7500);

      await handler.pause();
      expect(repo.lastSavedPos?.positionMs, 7500);

      player.currentPos = const Duration(milliseconds: 9000);
      await handler.stop();
      expect(repo.lastSavedPos?.positionMs, 9000);

      player.currentPos = const Duration(milliseconds: 14000);
      player.emitStatus(QuranPlaybackStatus.completed);
      await pumpEventQueue();
      expect(repo.lastSavedPos?.positionMs, 14000);

      player.currentPos = const Duration(milliseconds: 4000);
      await handler.onTaskRemoved();
      expect(repo.lastSavedPos?.positionMs, 4000);
    });

    test('AudioInterruptionType.duck ducks volume to 0.2 and restores to 1.0 on end', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // Duck begins (e.g. GPS prompt)
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.duck,
      ));
      await pumpEventQueue();

      expect(player.volume, 0.2);

      // Duck ends
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.duck,
      ));
      await pumpEventQueue();

      expect(player.volume, 1.0);
    });

    test('duck ending during active pause restores volume to 1.0 WITHOUT restarting playback', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // 1. Duck begins
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.duck,
      ));
      await pumpEventQueue();
      expect(player.volume, 0.2);

      // 2. Pause begins (incoming call while ducked)
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();
      expect(player.pauseCalled, isTrue);

      // 3. Duck ends before call ends
      player.playCalled = false;
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.duck,
      ));
      await pumpEventQueue();

      // Volume restored, but playback MUST REMAIN PAUSED
      expect(player.volume, 1.0);
      expect(player.playCalled, isFalse);
    });

    test('nested interruptions (Call 1 + Call 2) stay paused until all calls end', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // Call 1 begins
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();
      expect(player.pauseCalled, isTrue);

      // Call 2 begins (call waiting)
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      // Call 1 ends, but Call 2 is still active
      player.playCalled = false;
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      // MUST NOT resume yet
      expect(player.playCalled, isFalse);

      // Call 2 ends
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      // Now safe to resume
      expect(player.playCalled, isTrue);
    });

    test('manual user pause during interruption CANCELS auto-resume when interruption ends', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // Incoming call begins -> player pauses
      session.emitInterruption(AudioInterruptionEvent(
        true,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      // While on call, user opens app and explicitly taps pause
      await handler.pause();

      // Call ends
      player.playCalled = false;
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      // MUST NOT resume playback
      expect(player.playCalled, isFalse);
    });

    test('becomingNoisy (unplugged headphones) immediately pauses and prevents auto-resume', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      player.pauseCalled = false;
      session.emitBecomingNoisy();
      await pumpEventQueue();

      expect(player.pauseCalled, isTrue);

      // Any later interruption end must not resume
      player.playCalled = false;
      session.emitInterruption(AudioInterruptionEvent(
        false,
        AudioInterruptionType.pause,
      ));
      await pumpEventQueue();

      expect(player.playCalled, isFalse);
    });

    test('QuranAudioServiceInitializer concurrent initialize() requests share the exact same Future', () async {
      final futures = [
        QuranAudioServiceInitializer.initialize(
          player: player,
          getSurahAudioUseCase: getSurahAudioUseCase,
          isTestMode: true,
        ),
        QuranAudioServiceInitializer.initialize(
          player: player,
          getSurahAudioUseCase: getSurahAudioUseCase,
          isTestMode: true,
        ),
        QuranAudioServiceInitializer.initialize(
          player: player,
          getSurahAudioUseCase: getSurahAudioUseCase,
          isTestMode: true,
        ),
      ];

      final results = await Future.wait(futures);

      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[1], results[2]), isTrue);
    });

    test('QuranAudioServiceInitializer failure resets future allowing clean retry', () async {
      QuranAudioServiceInitializer.resetForTesting();

      // 1. Simulate failure on first attempt
      QuranAudioServiceInitializer.customInitializer = () async {
        throw Exception('Service initialization crashed');
      };

      bool didThrow = false;
      try {
        await QuranAudioServiceInitializer.initialize(
          player: player,
          getSurahAudioUseCase: getSurahAudioUseCase,
          isTestMode: true,
        );
      } catch (e) {
        didThrow = true;
      }

      expect(didThrow, isTrue);

      // 2. Clear failure mock for second attempt
      QuranAudioServiceInitializer.customInitializer = null;

      // 3. Second attempt succeeds cleanly
      final recoveredHandler = await QuranAudioServiceInitializer.initialize(
        player: player,
        getSurahAudioUseCase: getSurahAudioUseCase,
        isTestMode: true,
      );

      expect(recoveredHandler, isNotNull);
    });

    test('QA3-FV-01: Concurrent failure race condition: Late-resolving caller B does not wipe caller C retry future', () async {
      QuranAudioServiceInitializer.resetForTesting();

      final completer1 = Completer<QuranAudioHandler>();
      QuranAudioServiceInitializer.customInitializer = () => completer1.future;

      // Caller A and Caller B listen to the same initial future
      final futureA = QuranAudioServiceInitializer.initialize(player: player, isTestMode: true);
      final futureB = QuranAudioServiceInitializer.initialize(player: player, isTestMode: true);

      // Now complete with error
      completer1.completeError(Exception('First attempt failed'));

      // Caller A handles failure
      try {
        await futureA;
      } catch (_) {}

      // Caller C immediately starts a NEW retry
      final recoveredInstance = QuranAudioHandler(player: player);
      QuranAudioServiceInitializer.customInitializer = () async => recoveredInstance;
      final futureC = QuranAudioServiceInitializer.initialize(player: player, isTestMode: true);

      // Now Caller B finishes awaiting the old failed future
      try {
        await futureB;
      } catch (_) {}

      // Caller C's future must NOT have been wiped out by Caller B's catch block!
      final handlerC = await futureC;
      expect(handlerC, equals(recoveredInstance));
      expect(identical(QuranAudioServiceInitializer.currentHandler, recoveredInstance), isTrue);
    });

    test('QA3-FV-02: Position Persistence: Atomic FIFO queue preserves correct ordering and newer position', () async {
      final savedPositions = <PlaybackPosition>[];
      final mockRepo = FakeRepoForHandler();
      mockRepo.savePositionCallback = (pos) async {
        // Simulate async delay to test FIFO ordering
        await Future.delayed(const Duration(milliseconds: 10));
        savedPositions.add(pos);
      };

      final customSaveUseCase = SavePlaybackPositionUseCase(mockRepo);
      final safeHandler = QuranAudioHandler(
        player: player,
        savePlaybackPositionUseCase: customSaveUseCase,
      );

      await safeHandler.playSurah(surahAudio: testSurah1);

      // Simulate sequential writes with increasing position
      player.currentPos = const Duration(seconds: 10);
      safeHandler.pause(); // Persists 10s

      player.currentPos = const Duration(seconds: 20);
      safeHandler.pause(); // Persists 20s

      player.currentPos = const Duration(seconds: 30);
      await safeHandler.stop(); // Persists 30s and awaits completion

      expect(savedPositions.isNotEmpty, isTrue);
      expect(savedPositions.last.positionMs, 30000);
      await safeHandler.disposeHandler();
    });

    test('QA3-FV-02: Position Persistence: Delayed write from old track never overwrites newly switched track', () async {
      final savedSurahs = <int>[];
      final mockRepo = FakeRepoForHandler();
      mockRepo.savePositionCallback = (pos) async {
        await Future.delayed(const Duration(milliseconds: 20));
        savedSurahs.add(pos.surahNumber);
      };

      final customSaveUseCase = SavePlaybackPositionUseCase(mockRepo);
      final safeHandler = QuranAudioHandler(
        player: player,
        savePlaybackPositionUseCase: customSaveUseCase,
      );

      // 1. Play Surah 1 and trigger persistence
      await safeHandler.playSurah(surahAudio: testSurah1);
      player.currentPos = const Duration(seconds: 15);
      safeHandler.pause();

      // 2. Immediately switch to Surah 2
      await safeHandler.playSurah(surahAudio: testSurah2);
      player.currentPos = const Duration(seconds: 5);
      await safeHandler.stop();

      // Final saved position belongs to the latest track (Surah 2)
      expect(savedSurahs.isNotEmpty, isTrue);
      expect(savedSurahs.last, 2);
      await safeHandler.disposeHandler();
    });

    test('QA3-FV-02: Position Persistence: Monotonic write ensures Write B wins if Write A is stale or completes late', () async {
      final writtenPositions = <int>[];
      final mockRepo = FakeRepoForHandler();
      final completerA = Completer<void>();

      mockRepo.savePositionCallback = (pos) async {
        if (pos.positionMs == 10000) {
          // Write A is intentionally delayed
          await completerA.future;
        }
        writtenPositions.add(pos.positionMs);
      };

      final safeHandler = QuranAudioHandler(
        player: player,
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(mockRepo),
      );

      await safeHandler.playSurah(surahAudio: testSurah1);

      // 1. Trigger Write A (10s)
      player.currentPos = const Duration(seconds: 10);
      safeHandler.pause();

      // 2. Immediately trigger Write B (30s) before Write A completes
      player.currentPos = const Duration(seconds: 30);
      safeHandler.pause();

      // 3. Complete Write A's delay
      completerA.complete();
      await pumpEventQueue();

      // Ensure all queued writes in handler have drained
      await safeHandler.stop();

      // Only Write B (30000ms) is written; stale Write A (10000ms) was discarded by the monotonic queue!
      expect(writtenPositions.contains(30000), isTrue);
      expect(writtenPositions.last, 30000);
      expect(writtenPositions.contains(10000), isFalse, reason: 'Stale Write A must be discarded in favor of newer Write B');

      await safeHandler.disposeHandler();
    });

    test('QA3-FV-03: Unified Generation Token: direct playSurah invalidates in-flight skipToNext fetch', () async {
      final fetchCompleter = Completer<Either<QuranAudioFailure, SurahAudio>>();
      final slowRepo = FakeRepoForHandler();
      slowRepo.getSurahAudioCallback = (surahNum, reciterId) => fetchCompleter.future;

      final customGetUseCase = GetSurahAudioUseCase(slowRepo);
      final tokenHandler = QuranAudioHandler(
        player: player,
        getSurahAudioUseCase: customGetUseCase,
      );

      await tokenHandler.playSurah(surahAudio: testSurah1);
      expect(tokenHandler.currentTrack?.surahNumber, 1);

      // 1. User triggers skipToNext (starts in-flight fetch for Surah 2)
      final skipFuture = tokenHandler.skipToNext();

      // 2. While fetch is pending, user directly plays Surah 112 from UI
      final testSurah112 = SurahAudio(
        surahNumber: 112,
        reciterId: '7',
        audioUrl: 'http://cdn/112.mp3',
        format: 'mp3',
        durationMs: 20000,
        ayahTimings: const [],
      );
      await tokenHandler.playSurah(surahAudio: testSurah112);
      expect(tokenHandler.currentTrack?.surahNumber, 112);

      // 3. Now the slow skipToNext completes with Surah 2
      fetchCompleter.complete(Right(testSurah2));
      await skipFuture;
      await pumpEventQueue();

      // 4. Invalidation guard: The stale Surah 2 MUST be discarded; active track remains Surah 112!
      expect(tokenHandler.currentTrack?.surahNumber, 112);
      await tokenHandler.disposeHandler();
    });

    test('QA3-FV-03: Rapid double-tap policy: Debounce subsequent taps while navigation is in progress', () async {
      int fetchCallCount = 0;
      final slowRepo = FakeRepoForHandler();
      slowRepo.getSurahAudioCallback = (surahNum, reciterId) async {
        fetchCallCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return Right(testSurah2);
      };

      final customGetUseCase = GetSurahAudioUseCase(slowRepo);
      final debounceHandler = QuranAudioHandler(
        player: player,
        getSurahAudioUseCase: customGetUseCase,
      );

      await debounceHandler.playSurah(surahAudio: testSurah1);

      // Rapidly tap skipToNext twice in immediate succession
      final tap1 = debounceHandler.skipToNext();
      final tap2 = debounceHandler.skipToNext(); // Should be debounced!

      await Future.wait([tap1, tap2]);

      // Exactly 1 fetch must have been initiated
      expect(fetchCallCount, 1);
      expect(debounceHandler.currentTrack?.surahNumber, 2);
      await debounceHandler.disposeHandler();
    });

    test('QA3-FV-06: Interleaved Interruption: Duck begins, Call begins, Duck ends while Call active', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      player.volume = 1.0;
      await pumpEventQueue();

      // 1. Duck begins: Volume drops to 0.2
      session.emitInterruption(AudioInterruptionEvent(true, AudioInterruptionType.duck));
      await pumpEventQueue();
      expect(player.volume, 0.2);
      expect(handler.isDucked, isTrue);

      // 2. Call begins: Audio pauses
      player.pauseCalled = false;
      session.emitInterruption(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await pumpEventQueue();
      expect(player.pauseCalled, isTrue);
      expect(handler.isInterrupted, isTrue);

      // 3. Duck ends while Call is still ongoing: Volume restores to 1.0, but playback stays paused!
      player.playCalled = false;
      session.emitInterruption(AudioInterruptionEvent(false, AudioInterruptionType.duck));
      await pumpEventQueue();
      expect(player.volume, 1.0);
      expect(handler.isDucked, isFalse);
      expect(player.playCalled, isFalse); // Stays paused because call is still active!

      // 4. Call ends: Now playback safely resumes at full volume 1.0
      session.emitInterruption(AudioInterruptionEvent(false, AudioInterruptionType.pause));
      await pumpEventQueue();
      expect(player.playCalled, isTrue);
      expect(player.volume, 1.0);
      expect(handler.isInterrupted, isFalse);
    });

    test('QA3-FV-06: Duck ends while playback is paused does NOT restart playback', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.paused);
      await pumpEventQueue();

      player.playCalled = false;
      // Duck event arrives
      session.emitInterruption(AudioInterruptionEvent(true, AudioInterruptionType.duck));
      await pumpEventQueue();

      session.emitInterruption(AudioInterruptionEvent(false, AudioInterruptionType.duck));
      await pumpEventQueue();

      expect(player.playCalled, isFalse);
    });

    test('QA4-DEFECT-FIX: skipToNext / skipToPrevious completes non-blocking and enables subsequent play/pause without hang', () async {
      await handler.playSurah(surahAudio: testSurah1);
      player.emitStatus(QuranPlaybackStatus.playing);
      await pumpEventQueue();

      // 1. External skip to next track
      await handler.skipToNext();
      await pumpEventQueue();

      // Verify navigation flag reset and new surah loaded
      expect(handler.isNavigating, isFalse);
      expect(handler.currentTrack?.surahNumber, 2);

      // 2. Play/Pause immediately responds without deadlock
      player.pauseCalled = false;
      await handler.pause();
      expect(player.pauseCalled, isTrue);

      player.playCalled = false;
      await handler.play();
      expect(player.playCalled, isTrue);

      // 3. Subsequent skipToPrevious works cleanly
      await handler.skipToPrevious();
      await pumpEventQueue();
      expect(handler.isNavigating, isFalse);
      expect(handler.currentTrack?.surahNumber, 1);
    });
  });
}
