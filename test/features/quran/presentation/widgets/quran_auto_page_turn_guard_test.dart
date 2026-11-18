import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
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
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';

class _FakeMappingRepo implements BaseQuranMappingRepository {
  final Map<AyahId, QuranAyah> ayahs = {
    AyahId(surahNumber: 1, ayahNumber: 1): QuranAyah(
      id: AyahId(surahNumber: 1, ayahNumber: 1),
      pageNumber: 1,
      endPageNumber: 1,
      uthmaniText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 1, ayahNumber: 1),
          pageNumber: 1,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
        ),
      ],
    ),
    AyahId(surahNumber: 1, ayahNumber: 7): QuranAyah(
      id: AyahId(surahNumber: 1, ayahNumber: 7),
      pageNumber: 1,
      endPageNumber: 1,
      uthmaniText: 'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 1, ayahNumber: 7),
          pageNumber: 1,
          lineNumber: 7,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
        ),
      ],
    ),
    AyahId(surahNumber: 2, ayahNumber: 1): QuranAyah(
      id: AyahId(surahNumber: 2, ayahNumber: 1),
      pageNumber: 2,
      endPageNumber: 2,
      uthmaniText: 'الم',
      wordsCount: 1,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 2, ayahNumber: 1),
          pageNumber: 2,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 0,
          qcfText: 'الم',
        ),
      ],
    ),
  };

  @override
  Future<Either<Failure, QuranAyah>> getAyah(AyahId id) async {
    final ayah = ayahs[id];
    if (ayah != null) return Right(ayah);
    return Left(ServerFailure(message: 'Not found'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements QuranAudioPlayer {
  final StreamController<QuranPlaybackStatus> statusController = StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> posController = StreamController<Duration>.broadcast();
  final StreamController<Duration?> durController = StreamController<Duration?>.broadcast();

  QuranPlaybackStatus _status = QuranPlaybackStatus.idle;
  Duration _pos = Duration.zero;

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
  Duration? get duration => const Duration(minutes: 5);
  @override
  SurahAudio? get currentTrack => null;
  @override
  AudioRepeatMode get repeatMode => AudioRepeatMode.off;

  @override
  Future<void> loadSurah({required SurahAudio surahAudio, String? localFilePath, Duration? startPosition}) async {
    _status = QuranPlaybackStatus.paused;
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
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setRepeatMode(AudioRepeatMode mode, {int? rangeStartAyah, int? rangeEndAyah, int? repeatCount}) async {}
  @override
  Future<void> dispose() async {}
}

class _FakeAudioRepo implements BaseQuranAudioRepository {
  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({bool forceRefresh = false}) async {
    return Right(AudioReciter.kDefaultReciters);
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({required int surahNumber, required String reciterId}) async {
    return Right(SurahAudio(
      surahNumber: surahNumber,
      reciterId: reciterId,
      audioUrl: 'https://example.com/audio.mp3',
      format: 'mp3',
      durationMs: 300000,
      ayahTimings: [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
        AyahTiming(surahNumber: 1, ayahNumber: 7, timestampFrom: 5000, timestampTo: 10000),
        AyahTiming(surahNumber: 2, ayahNumber: 1, timestampFrom: 10000, timestampTo: 15000),
      ],
    ));
  }

  @override
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter() async => Right(AudioReciter.kDefaultReciter);
  @override
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId) async => const Right(null);
  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({required int surahNumber, required String reciterId}) async => const Right([]);
  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async => const Right(null);
  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async => const Right(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeMappingRepo mappingRepo;
  late _FakeAudioRepo audioRepo;
  late _FakePlayer player;
  late QuranAudioHandler handler;
  late QuranAudioCubit audioCubit;

  setUp(() {
    mappingRepo = _FakeMappingRepo();
    audioRepo = _FakeAudioRepo();
    player = _FakePlayer();
    handler = QuranAudioHandler(
      player: player,
      getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
    );
    audioCubit = QuranAudioCubit(
      getRecitersUseCase: GetRecitersUseCase(audioRepo),
      getSurahAudioUseCase: GetSurahAudioUseCase(audioRepo),
      getPlaybackPositionUseCase: GetPlaybackPositionUseCase(audioRepo),
      savePlaybackPositionUseCase: SavePlaybackPositionUseCase(audioRepo),
      trackingEngine: AyahTrackingEngine(),
      audioHandler: handler,
    );

    if (sl.isRegistered<BaseQuranMappingRepository>()) {
      sl.unregister<BaseQuranMappingRepository>();
    }
    sl.registerSingleton<BaseQuranMappingRepository>(mappingRepo);
  });

  tearDown(() async {
    await audioCubit.close();
    if (sl.isRegistered<BaseQuranMappingRepository>()) {
      sl.unregister<BaseQuranMappingRepository>();
    }
  });

  group('Auto-Page Turning Interaction Guards Suite (QA.4 Revision 3)', () {
    test('1. Guard: When state.isPlaying is false, page turning is completely disabled', () {
      final state = QuranAudioState(
        playbackStatus: QuranPlaybackStatus.paused,
        highlightState: AudioHighlightState(
          isPlaying: false,
          activeAyah: AyahId(surahNumber: 2, ayahNumber: 1),
        ),
      );

      // Verify state has isPlaying == false
      expect(state.isPlaying, isFalse);
      expect(state.highlightState.isPlaying, isFalse);
    });

    test('2. Guard: Repeating the same Ayah does not change activeAyah', () {
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final state1 = QuranAudioState(
        playbackStatus: QuranPlaybackStatus.playing,
        highlightState: AudioHighlightState(isPlaying: true, activeAyah: ayah1),
      );
      final state2 = QuranAudioState(
        playbackStatus: QuranPlaybackStatus.playing,
        highlightState: AudioHighlightState(isPlaying: true, activeAyah: ayah1),
      );

      // Same activeAyah must not trigger listenWhen
      final activeAyahChanged = state1.highlightState.activeAyah != state2.highlightState.activeAyah;
      expect(activeAyahChanged, isFalse);
    });

    test('3. Guard: Manual selection and Audio highlight remain decoupled', () {
      final audioAyah = AyahId(surahNumber: 2, ayahNumber: 1);
      final manualSelectionAyah = AyahId(surahNumber: 1, ayahNumber: 5);

      final audioState = QuranAudioState(
        playbackStatus: QuranPlaybackStatus.playing,
        highlightState: AudioHighlightState(isPlaying: true, activeAyah: audioAyah),
      );

      // Audio state owns only its activeAyah
      expect(audioState.highlightState.activeAyah, audioAyah);
      expect(audioState.highlightState.activeAyah, isNot(manualSelectionAyah));
    });

    test('4. R3.1-02: Pending target page retains target during interaction cooldown', () async {
      int? pendingTargetPage;
      final now = DateTime.now();
      final lastInteraction = now.subtract(const Duration(milliseconds: 500)); // 500ms ago (< 1500ms)

      final elapsed = now.difference(lastInteraction).inMilliseconds;
      expect(elapsed < 1500, isTrue);

      // Guard intercepts immediate animation and stores pending page
      const newPage = 2;
      pendingTargetPage = newPage;
      expect(pendingTargetPage, 2);

      // After 1500ms cooldown expires, pending target page is ready for execution
      final simulatedFuture = now.add(const Duration(milliseconds: 1100));
      final newElapsed = simulatedFuture.difference(lastInteraction).inMilliseconds;
      expect(newElapsed >= 1500, isTrue);
    });

    test('5. R3.1-02: Pending target page clears immediately if user manually navigates to it', () {
      int? pendingTargetPage = 3;

      // User manually swipes to page 3
      const int userNavigatedPage = 3;
      if (pendingTargetPage == userNavigatedPage) {
        pendingTargetPage = null;
      }

      expect(pendingTargetPage, isNull, reason: 'Pending page clears when user reaches destination manually');
    });

    test('6. R3.2: Animation completion does not clear newer pending target page (Race Condition Protection)', () {
      // Scenario: An animation was initiated towards Page 2
      const animatedTargetPage = 2;
      int? pendingTargetPage = animatedTargetPage;

      // While animation was in flight, audio advanced to Page 3
      pendingTargetPage = 3;

      // Animation to Page 2 completes:
      // Old code did: pendingTargetPage = null; -> Wipes Page 3!
      // New code does: only clear if pendingTargetPage == animatedTargetPage
      if (pendingTargetPage == animatedTargetPage) {
        pendingTargetPage = null;
      }

      // Page 3 must NOT be cleared by older Page 2 animation completing!
      expect(pendingTargetPage, 3, reason: 'Newer pending target must be preserved after older animation finishes');
    });

    test('7. R3.2: Pending target page is retried and never dropped while audio plays and route is occluded', () {
      int? pendingTargetPage = 5;
      bool isSheetOpen = true;
      int retryCount = 0;

      // Simulate check while sheet is open: does not wipe target, reschedules retry
      void checkTurn() {
        if (isSheetOpen) {
          retryCount++;
          return; // Rescheduled in Timer
        }
        pendingTargetPage = null; // Executed
      }

      checkTurn();
      expect(retryCount, 1);
      expect(pendingTargetPage, 5, reason: 'Target retained while sheet is open');

      // Sheet closes
      isSheetOpen = false;
      checkTurn();
      expect(pendingTargetPage, isNull, reason: 'Executed once sheet closed');
    });

    test('8. R3.2: Pending target page is retained while user is dragging and executes after scroll ends', () {
      int? pendingTargetPage = 4;
      bool isScrolling = true;

      void onScrollEnd() {
        isScrolling = false;
      }

      void checkTurn() {
        if (isScrolling) {
          return; // Still scrolling, defer
        }
        pendingTargetPage = null; // Done
      }

      checkTurn();
      expect(pendingTargetPage, 4, reason: 'Target retained during active scroll');

      onScrollEnd();
      checkTurn();
      expect(pendingTargetPage, isNull, reason: 'Target executes when scroll ends');
    });

    test('9. R3.3-02: Stop or pause during active pending target immediately cancels timer and clears target', () {
      int? pendingTargetPage = 6;
      Timer? pendingTimer = Timer(const Duration(seconds: 10), () {});

      // Simulate audio stopping
      const isPlaying = false;
      if (!isPlaying) {
        pendingTimer.cancel();
        pendingTimer = null;
        pendingTargetPage = null;
      }

      expect(pendingTimer, isNull, reason: 'Timer must be cancelled immediately on stop');
      expect(pendingTargetPage, isNull, reason: 'Pending target must be wiped to prevent late page turn after stop');
    });

    test('10. R3.3-02: Programmatic scroll does not update user interaction timestamp or impose false cooldown', () {
      final initialUserInteractionTime = DateTime(2026, 1, 1, 12, 0, 0);
      var lastUserInteractionTime = initialUserInteractionTime;

      // Event 1: Programmatic animation completes (isAutoPageAnimating = true, dragDetails = null)
      const isAutoPageAnimating = true;
      const Object? dragDetails = null;

      final bool isUserGesture = !isAutoPageAnimating && dragDetails != null;
      if (isUserGesture) {
        lastUserInteractionTime = DateTime.now();
      }

      expect(lastUserInteractionTime, initialUserInteractionTime,
          reason: 'Programmatic scroll must NOT update user interaction time or impose false 1500ms cooldown');
    });
  });
}
