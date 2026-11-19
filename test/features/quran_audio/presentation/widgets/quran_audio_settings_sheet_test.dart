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
import 'package:hafiz_al_ahd/features/quran_audio/presentation/widgets/quran_audio_settings_sheet.dart';

class _FakeRepo implements BaseQuranAudioRepository {
  List<AudioReciter> reciters = [
    AudioReciter(
      id: '7',
      name: 'Mishari Rashid al-`Afasy',
      arabicName: 'مشاري العفاسي',
      style: 'Murattal',
    ),
    AudioReciter(
      id: '1',
      name: 'AbdulBaset AbdulSamad',
      arabicName: 'عبد الباسط عبد الصمد',
      style: 'Mujawwad',
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

  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({bool forceRefresh = false}) async {
    return Right(reciters);
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
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

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BlocProvider<QuranAudioCubit>.value(
            value: cubit,
            child: const QuranAudioSettingsSheet(),
          ),
        ),
      ),
    );
  }

  group('QuranAudioSettingsSheet Reading & Memorization Settings (QA.4)', () {
    testWidgets('1. Renders header, reciter list, repeat mode options, and memorization chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Header
      expect(find.text('إعدادات التلاوة والحفظ'), findsOneWidget);

      // Reciters section
      expect(find.text('مشاري العفاسي'), findsOneWidget);
      expect(find.text('عبد الباسط عبد الصمد'), findsOneWidget);

      // Repeat mode scope options
      expect(find.text('مستمر'), findsOneWidget);
      expect(find.text('سورة كاملة'), findsOneWidget);
      expect(find.text('تكرار سورة'), findsOneWidget);
      expect(find.text('تكرار آية'), findsOneWidget);
      expect(find.text('نطاق (حفظ)'), findsOneWidget);

      // Tap on 'تكرار آية' to reveal memorization repeat chips
      await tester.tap(find.text('تكرار آية'));
      await tester.pump(const Duration(milliseconds: 50));

      // Memorization chips
      expect(find.text('مرة واحدة'), findsOneWidget);
      expect(find.text('مرتان'), findsOneWidget);
      expect(find.text('٣ مرات'), findsOneWidget);
      expect(find.text('٥ مرات'), findsOneWidget);
      expect(find.text('١٠ مرات'), findsOneWidget);
      expect(find.text('مستمر ∞'), findsOneWidget);

      // Action button
      expect(find.text('حفظ وتطبيق الإعدادات'), findsOneWidget);
    });

    testWidgets('2. Selecting a different reciter updates selected reciter in Cubit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.state.selectedReciter?.id, equals('7'));

      // Tap on AbdulBaset AbdulSamad
      final abdulBasetCard = find.text('عبد الباسط عبد الصمد');
      await tester.tap(abdulBasetCard);
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.state.selectedReciter?.id, equals('1'));
    });

    testWidgets('3. Switching to range mode displays From and To Ayah steppers', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Initially range steppers are not visible
      expect(find.text('من الآية'), findsNothing);
      expect(find.text('إلى الآية'), findsNothing);

      // Tap on 'نطاق (حفظ)'
      final rangeModeBtn = find.text('نطاق (حفظ)');
      await tester.tap(rangeModeBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Range steppers are now visible
      expect(find.text('من الآية'), findsOneWidget);
      expect(find.text('إلى الآية'), findsOneWidget);
    });

    testWidgets('4. Tapping Apply Settings applies repeat mode to Cubit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 50));

      // Select Single Ayah Repeat mode
      await tester.tap(find.text('تكرار آية'));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap Apply Settings
      final applyBtn = find.text('حفظ وتطبيق الإعدادات');
      await tester.tap(applyBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Verify Cubit repeat mode is updated
      expect(cubit.state.highlightState.repeatMode, equals(AudioRepeatMode.singleAyah));
    });
  });
}
