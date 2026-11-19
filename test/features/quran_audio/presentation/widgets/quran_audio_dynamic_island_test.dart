import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:hafiz_al_ahd/features/quran_audio/presentation/widgets/quran_audio_dynamic_island.dart';

class _FakeRepo implements BaseQuranAudioRepository {
  List<AudioReciter> reciters = [
    AudioReciter(
      id: '7',
      name: 'Mishari Rashid al-`Afasy',
      arabicName: 'مشاري العفاسي',
      style: 'Murattal',
    ),
  ];

  SurahAudio surah1 = SurahAudio(
    surahNumber: 1,
    audioUrl: 'https://cdn.example.com/audio/001.mp3',
    durationMs: 15000,
    reciterId: '7',
    format: 'mp3',
    ayahTimings: [
      AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
      AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5000, timestampTo: 10000),
      AyahTiming(surahNumber: 1, ayahNumber: 3, timestampFrom: 10000, timestampTo: 15000),
    ],
  );

  final surah2 = SurahAudio(
    surahNumber: 2,
    reciterId: '7',
    audioUrl: 'https://example.com/2.mp3',
    format: 'mp3',
    durationMs: 120000,
    ayahTimings: [
      AyahTiming(surahNumber: 2, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
    ],
  );

  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({bool forceRefresh = false}) async {
    return Right(reciters);
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (surahNumber == 2) return Right(surah2);
    return Right(surah1);
  }

  @override
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter() async => Right(reciters.first);

  @override
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId) async => const Right(null);

  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  }) async => Right(surah1.ayahTimings);

  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async => const Right(null);

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async => const Right(null);
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
  double volume = 1.0;

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

  @override
  Future<void> loadSurah({required SurahAudio surahAudio, String? localFilePath, Duration? startPosition}) async {
    _track = surahAudio;
    _dur = Duration(milliseconds: surahAudio.durationMs);
    durController.add(_dur);
    _pos = startPosition ?? Duration.zero;
    posController.add(_pos);
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
    _pos = Duration.zero;
    posController.add(_pos);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _pos = position;
    posController.add(_pos);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo fakeRepo;
  late _FakePlayer fakePlayer;
  late QuranAudioHandler handler;
  late AyahTrackingEngine trackingEngine;
  late QuranAudioCubit cubit;

  setUp(() async {
    fakeRepo = _FakeRepo();
    fakePlayer = _FakePlayer();
    handler = QuranAudioHandler(
      player: fakePlayer,
      getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
    );
    trackingEngine = AyahTrackingEngine();

    cubit = QuranAudioCubit(
      getRecitersUseCase: GetRecitersUseCase(fakeRepo),
      getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
      getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeRepo),
      savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeRepo),
      trackingEngine: trackingEngine,
      audioHandler: handler,
    );

    await cubit.init();
    await cubit.playSurah(surahNumber: 1);
  });

  tearDown(() async {
    await cubit.close();
  });

  Widget buildTestWidget({
    VoidCallback? onSettingsTap,
    int? defaultSurahNumber,
    bool isFullScreen = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BlocProvider<QuranAudioCubit>.value(
            value: cubit,
            child: QuranAudioDynamicIsland(
              key: ValueKey(defaultSurahNumber ?? -1),
              onSettingsTap: onSettingsTap,
              defaultSurahNumber: defaultSurahNumber,
              isFullScreen: isFullScreen,
            ),
          ),
        ),
      ),
    );
  }

  group('QuranAudioDynamicIsland UI & Interaction Verification (QA.4)', () {
    testWidgets('1. Collapsed pill renders Surah name, Ayah badge, soundwave, and Play icon', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pause playback so play icon is visible
      await cubit.pause();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Collapsed pill is visible
      expect(find.byType(QuranAudioDynamicIsland), findsOneWidget);
      expect(find.text('سورة الفاتحة'), findsOneWidget);
      expect(find.text('الآية 1'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('2. Double-tap toggles Play / Pause without expanding pill', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pause initially
      await cubit.pause();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.isPlaying, isFalse);

      // Perform double tap on the collapsed island
      final islandFinder = find.byType(QuranAudioDynamicIsland);
      await tester.tap(islandFinder);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(islandFinder);
      await tester.pump(const Duration(milliseconds: 100));

      // Verify playback started
      expect(cubit.state.isPlaying, isTrue);

      // Verify still collapsed: expanded details not rendered
      expect(find.text('المدة المتبقية'), findsNothing);
      expect(find.text('مشاري العفاسي'), findsNothing);
    });

    testWidgets('3. Single-tap pops open expanded view with details & remaining time', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Single tap to expand (wait for double-tap window then animation)
      final islandFinder = find.byType(QuranAudioDynamicIsland);
      await tester.tap(islandFinder);
      await tester.pump(const Duration(milliseconds: 350)); // resolve double-tap gesture
      await tester.pump(const Duration(milliseconds: 350)); // resolve expand animation

      // Expanded details view now visible
      expect(find.text('سورة الفاتحة'), findsWidgets);
      expect(find.text('مشاري العفاسي'), findsOneWidget);
      expect(find.text('المتبقي: '), findsOneWidget);
      expect(find.text('-00:15'), findsOneWidget); // 15s total remaining at 0:00
      expect(find.byType(Slider), findsOneWidget);

      // Playback action buttons
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget); // prev surah
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget); // rewind 10s
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget); // forward 10s
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget); // next surah
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget); // stop

      // Collapse back by tapping close chevron
      final closeBtnFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
      expect(closeBtnFinder, findsOneWidget);
      await tester.tap(closeBtnFinder);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      // Collapsed again
      expect(find.text('المتبقي: '), findsNothing);
    });

    testWidgets('4. Rewind and Forward 10s buttons seek properly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Expand
      await tester.tap(find.byType(QuranAudioDynamicIsland));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      // Seek to 12s first
      await cubit.seekTo(const Duration(seconds: 12));
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.currentPosition.inSeconds, equals(12));

      // Tap Rewind 10s -> should seek to 2s
      final rewindBtn = find.byIcon(Icons.replay_10_rounded);
      await tester.tap(rewindBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.currentPosition.inSeconds, equals(2));

      // Tap Forward 10s -> should seek to 12s
      final forwardBtn = find.byIcon(Icons.forward_10_rounded);
      await tester.tap(forwardBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.currentPosition.inSeconds, equals(12));
    });

    testWidgets('5. Quick repeat button cycles through repeat modes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Expand
      await tester.tap(find.byType(QuranAudioDynamicIsland));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.continuous));

      final repeatBtn = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            (w.tooltip?.contains('تلاوة مستمرة') == true ||
                w.tooltip?.contains('تكرار') == true ||
                w.tooltip == 'سورة كاملة فقط'),
      );

      // Tap 1: continuous -> surah
      await tester.tap(repeatBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.surah));

      // Tap 2: surah -> singleAyah
      await tester.tap(repeatBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.singleAyah));

      // Tap 3: singleAyah -> range
      await tester.tap(repeatBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.range));

      // Tap 4: range -> off
      await tester.tap(repeatBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.off));

      // Tap 5: off -> continuous
      await tester.tap(repeatBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.continuous));
    });

    testWidgets('6. Long-press triggers onSettingsTap callback', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool settingsTriggered = false;
      await tester.pumpWidget(buildTestWidget(
        onSettingsTap: () => settingsTriggered = true,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Perform long press
      await tester.longPress(find.byType(QuranAudioDynamicIsland));
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsTriggered, isTrue);
    });

    testWidgets('7. Direct tap on mini play icon in collapsed pill immediately triggers togglePlayPause', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pause initially
      await cubit.pause();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));
      expect(cubit.state.isPlaying, isFalse);

      // Tap directly on the mini play icon and allow gesture arena timeout (300ms) to resolve
      final playIconFinder = find.byIcon(Icons.play_arrow_rounded);
      expect(playIconFinder, findsOneWidget);
      await tester.tap(playIconFinder);
      await tester.pump(const Duration(milliseconds: 350));

      // Playback started immediately without expanding
      expect(cubit.state.isPlaying, isTrue);
      expect(find.text('المدة المتبقية'), findsNothing);
    });

    testWidgets('8. Entering fullscreen automatically collapses expanded dynamic island', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Initially not in fullscreen
      await tester.pumpWidget(buildTestWidget(isFullScreen: false));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap island to expand
      final islandFinder = find.byType(QuranAudioDynamicIsland);
      await tester.tap(islandFinder);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      // Verify expanded
      expect(find.text('مشاري العفاسي'), findsOneWidget);

      // Re-pump widget with isFullScreen: true
      await tester.pumpWidget(buildTestWidget(isFullScreen: true));
      await tester.pump(const Duration(milliseconds: 350));

      // Island collapsed automatically
      expect(find.text('مشاري العفاسي'), findsNothing);
    });

    testWidgets('9. Resolves default surah from active page if no audio was loaded yet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Fresh player and handler with zero tracks ever loaded
      final freshPlayer = _FakePlayer();
      final freshHandler = QuranAudioHandler(
        player: freshPlayer,
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
      );
      final freshCubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeRepo),
        trackingEngine: AyahTrackingEngine(),
        audioHandler: freshHandler,
      );
      addTearDown(() => freshCubit.close());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BlocProvider<QuranAudioCubit>.value(
                value: freshCubit,
                child: const QuranAudioDynamicIsland(
                  defaultSurahNumber: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('سورة آل عمران'), findsOneWidget);
    });

    testWidgets('10. Stop clears active track and reflects newly opened page title', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Play Surah 1
      await cubit.playSurah(surahNumber: 1);
      await tester.pumpWidget(buildTestWidget(defaultSurahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('سورة الفاتحة'), findsOneWidget);

      // 2. Stop playback
      await cubit.stop();
      await tester.pump(const Duration(milliseconds: 50));

      // 3. User navigates to page for Surah 2 (Al-Baqarah)
      await tester.pumpWidget(buildTestWidget(defaultSurahNumber: 2));
      await tester.pump(const Duration(milliseconds: 50));

      // 4. Island must reflect the visible page's Surah
      expect(find.text('سورة البقرة'), findsOneWidget);

      // 5. Direct tap on mini play icon starts playback of Surah 2
      final playIconFinder = find.byIcon(Icons.play_arrow_rounded);
      expect(playIconFinder, findsOneWidget);
      await tester.tap(playIconFinder);
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.state.currentSurahNumber, 2);
    });
  });
}
