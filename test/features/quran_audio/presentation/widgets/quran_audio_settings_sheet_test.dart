import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/storage_reconciliation_summary.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_audio_download_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_quran_audio_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_reciters_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_surah_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/save_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_cubit.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/widgets/quran_audio_settings_sheet.dart';

class _FakeDownloadService implements BaseQuranAudioDownloadService {
  final Map<String, StreamController<DownloadProgress>> controllers = {};
  final Map<String, DownloadProgress> latest = {};
  int downloadCalls = 0;
  int pauseCalls = 0;
  int cancelCalls = 0;

  StreamController<DownloadProgress> _getController(
      int surahNumber, String reciterId) {
    final key = '$reciterId:$surahNumber';
    return controllers.putIfAbsent(
        key, () => StreamController<DownloadProgress>.broadcast());
  }

  void emitProgress(DownloadProgress progress) {
    final key = '${progress.reciterId}:${progress.surahNumber}';
    latest[key] = progress;
    _getController(progress.surahNumber, progress.reciterId).add(progress);
  }

  @override
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  }) {
    downloadCalls++;
    final c = _getController(surahNumber, reciterId);
    return c.stream;
  }

  @override
  Future<void> pauseDownload(int surahNumber, String reciterId) async {
    pauseCalls++;
  }

  @override
  Future<void> cancelDownload(int surahNumber, String reciterId) async {
    cancelCalls++;
  }

  @override
  Future<void> retryDownload({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  }) async {
    downloadCalls++;
  }

  @override
  DownloadProgress? getProgress(int surahNumber, String reciterId) {
    return latest['$reciterId:$surahNumber'];
  }

  @override
  Stream<DownloadProgress> watchProgress(int surahNumber, String reciterId) {
    return _getController(surahNumber, reciterId).stream;
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.close();
    }
  }
}

class _FakeDownloadRepository implements BaseAudioDownloadRepository {
  final Set<String> downloadedSurahs = {};
  int deleteCalls = 0;

  @override
  Future<bool> isSurahDownloaded(
      {required int surahNumber, required String reciterId}) async {
    return downloadedSurahs.contains('$reciterId:$surahNumber');
  }

  @override
  Future<Either<QuranAudioFailure, void>> deleteDownloadRecord({
    required int surahNumber,
    required String reciterId,
  }) async {
    deleteCalls++;
    downloadedSurahs.remove('$reciterId:$surahNumber');
    return const Right(null);
  }

  @override
  Future<List<AudioDownload>> getAllDownloadedRecords() async => [];

  @override
  Future<List<AudioDownload>> getDownloadedSurahs(
          {required String reciterId}) async =>
      [];

  @override
  Future<AudioDownload?> getDownloadRecord(
      {required int surahNumber, required String reciterId}) async {
    if (downloadedSurahs.contains('$reciterId:$surahNumber')) {
      return AudioDownload(
        surahNumber: surahNumber,
        reciterId: reciterId,
        localRelativePath: 'reciter_$reciterId/surah_$surahNumber.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 1000,
        sha256: 'fake_sha256_hash_1234567890abcdef',
        transferIntegrityVerified: true,
      );
    }
    return null;
  }

  @override
  Future<String?> getLocalAudioPath(
          {required int surahNumber, required String reciterId}) async =>
      null;

  @override
  Future<Either<QuranAudioFailure, StorageReconciliationSummary>>
      reconcileStorage() async {
    return const Right(StorageReconciliationSummary(
      discoveredFiles: 0,
      missingFiles: 0,
      cleanedTempFiles: 0,
    ));
  }

  @override
  Future<Either<QuranAudioFailure, void>> saveDownloadRecord(
          AudioDownload download) async =>
      const Right(null);

  @override
  Future<Either<QuranAudioFailure, void>> deleteAllDownloads() async =>
      const Right(null);

  @override
  Future<Either<QuranAudioFailure, void>> deleteReciterDownloads(
          {required String reciterId}) async =>
      const Right(null);
}

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
  late _FakeDownloadService fakeDownloadService;
  late _FakeDownloadRepository fakeDownloadRepo;
  late QuranAudioCubit cubit;

  setUp(() async {
    fakeRepo = _FakeRepo();
    fakePlayer = _FakePlayer();
    handler = QuranAudioHandler(
      player: fakePlayer,
      getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
    );
    trackingEngine = AyahTrackingEngine();
    fakeDownloadService = _FakeDownloadService();
    fakeDownloadRepo = _FakeDownloadRepository();

    cubit = QuranAudioCubit(
      getRecitersUseCase: GetRecitersUseCase(fakeRepo),
      getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
      getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeRepo),
      savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeRepo),
      trackingEngine: trackingEngine,
      audioHandler: handler,
      downloadService: fakeDownloadService,
      downloadRepository: fakeDownloadRepo,
    );

    await cubit.init();
    await cubit.playSurah(surahNumber: 1);
  });

  tearDown(() async {
    fakeDownloadService.dispose();
    await cubit.close();
  });

  Widget buildTestWidget({int? surahNumber}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BlocProvider<QuranAudioCubit>.value(
            value: cubit,
            child: QuranAudioSettingsSheet(surahNumber: surahNumber),
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

  group('QuranAudioSettingsSheet Single-Surah Offline Download (QA.5 Phase 5.5)', () {
    testWidgets('5. Renders single-Surah download section and initiates download on tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Verify download section header
      expect(find.text('تحميل السورة للاستماع دون إنترنت'), findsOneWidget);
      expect(find.text('تحميل السورة الآن'), findsOneWidget);
      expect(find.byKey(const Key('download_surah_button')), findsOneWidget);

      // Tap download button
      await tester.tap(find.byKey(const Key('download_surah_button')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakeDownloadService.downloadCalls, equals(1));
    });

    testWidgets('6. Renders downloading progress bar, pause and cancel buttons when downloading', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap download button to initiate pipeline
      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Emit downloading progress
      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 450000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Verify progress UI
      final pauseBtn = find.byKey(const Key('download_pause_button'));
      final cancelBtn = find.byKey(const Key('download_cancel_button'));
      await tester.ensureVisible(pauseBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download_progress_bar')), findsOneWidget);
      expect(pauseBtn, findsOneWidget);
      expect(cancelBtn, findsOneWidget);

      // Tap pause button
      await tester.tap(pauseBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(fakeDownloadService.pauseCalls, equals(1));

      // Tap cancel button
      await tester.ensureVisible(cancelBtn);
      await tester.pump();
      await tester.tap(cancelBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(fakeDownloadService.cancelCalls, equals(1));
    });

    testWidgets('7. Renders paused state with resume and cancel buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Emit paused progress
      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.paused,
        downloadedBytes: 450000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final resumeBtn = find.byKey(const Key('download_resume_button'));
      await tester.ensureVisible(resumeBtn);
      await tester.pump();

      expect(find.byKey(const Key('download_paused_progress_bar')), findsOneWidget);
      expect(resumeBtn, findsOneWidget);
      expect(find.byKey(const Key('download_cancel_paused_button')), findsOneWidget);

      // Tap resume
      await tester.tap(resumeBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(fakeDownloadService.downloadCalls, equals(2));
    });

    testWidgets('8. Renders verifying state during SHA-256 integrity check', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.verifying,
        downloadedBytes: 1000000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final verifyingRow = find.byKey(const Key('download_verifying_row'));
      await tester.ensureVisible(verifyingRow);
      await tester.pump(const Duration(milliseconds: 50));

      expect(verifyingRow, findsOneWidget);
      expect(find.text('التحقق من صحة الملف والترقية الذرية...'), findsOneWidget);
    });

    testWidgets('9. Renders completed state with offline indicator and delete button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.completed,
        downloadedBytes: 1000000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final completedRow = find.byKey(const Key('download_completed_row'));
      await tester.ensureVisible(completedRow);
      await tester.pump(const Duration(milliseconds: 50));

      expect(completedRow, findsOneWidget);
      expect(find.text('جاهزة للاستماع دون اتصال'), findsOneWidget);
      expect(find.byKey(const Key('delete_download_button')), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('delete_download_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(fakeDownloadRepo.deleteCalls, equals(1));
    });

    testWidgets('10. Renders failed state with error message and retry button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.failed,
        downloadedBytes: 0,
        lastError: 'انقطع الاتصال بالإنترنت',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final retryBtn = find.byKey(const Key('download_retry_button'));
      await tester.ensureVisible(retryBtn);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('انقطع الاتصال بالإنترنت'), findsOneWidget);
      expect(retryBtn, findsOneWidget);

      // Tap retry
      await tester.tap(retryBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(fakeDownloadService.downloadCalls, equals(2));
    });

    testWidgets('10B. Sanitizes raw technical SocketException into user-friendly Arabic error message', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(surahNumber: 112));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 112,
        reciterId: '7',
        status: AudioDownloadStatus.failed,
        downloadedBytes: 0,
        lastError: "ClientException with SocketException: Failed host lookup: 'download.quranicaudio.com' (OS Error: No address associated with hostname, errno = 7), uri=https://download.quranicaudio.com/quran/yasser_ad-dussary//112.mp3",
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Invariant: Raw exception text must NEVER be shown to user
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('Failed host lookup'), findsNothing);

      // Invariant: Clean friendly Arabic error message is displayed
      expect(
        find.text('تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.'),
        findsOneWidget,
      );
    });

    testWidgets('11. Reader switching race guard: Switching reciter isolates status and ignores delayed events from previous reciter', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Reciter 7 (Mishari) has completed download
      fakeDownloadRepo.downloadedSurahs.add('7:1');

      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Trigger post frame callback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Initially Reciter 7 is selected and completed
      expect(find.text('سورة الفاتحة — مشاري العفاسي'), findsOneWidget);
      final completedRow = find.byKey(const Key('download_completed_row'));
      await tester.ensureVisible(completedRow);
      await tester.pump();
      expect(completedRow, findsOneWidget);

      // Now switch to Reciter 1 (AbdulBasit)
      final reciter1Chip = find.text('عبد الباسط عبد الصمد');
      await tester.tap(reciter1Chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Reciter 1 is not downloaded
      expect(find.text('سورة الفاتحة — عبد الباسط عبد الصمد'), findsOneWidget);
      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pump();
      expect(downloadBtn, findsOneWidget);

      // Simulate delayed progress event arriving for Reciter 7 while Reciter 1 is active
      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 500000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // UI MUST still display Reciter 1 as notDownloaded, NOT Reciter 7's downloading progress
      expect(find.text('سورة الفاتحة — عبد الباسط عبد الصمد'), findsOneWidget);
      expect(find.byKey(const Key('download_surah_button')), findsOneWidget);
      expect(find.byKey(const Key('download_progress_bar')), findsNothing);

      // Switch back to Reciter 7
      cubit.selectReciter('7');
      await cubit.checkDownloadStatus(surahNumber: 1, reciterId: '7');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.state.getDownloadDisplayStatus(1, '7'), equals(AudioDownloadDisplayStatus.downloading));
      expect(find.textContaining('الفاتحة'), findsWidgets);
      expect(find.textContaining('العفاسي'), findsWidgets);
    });

    testWidgets('12. Surah resolution hierarchy: Explicit surahNumber takes precedence over playing track', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Playing track is Surah 18 (Al-Kahf)
      await cubit.playSurah(surahNumber: 18);

      // But sheet is opened with explicit surahNumber: 2 (Al-Baqarah, the reading page)
      await tester.pumpWidget(buildTestWidget(surahNumber: 2));
      await tester.pump(const Duration(milliseconds: 50));

      // Must target Al-Baqarah (2), NOT Al-Kahf (18)
      expect(find.textContaining('البقرة'), findsWidgets);
      expect(find.textContaining('الكهف'), findsNothing);
    });

    testWidgets('13. Download lifecycle independence: Download continues when Settings Sheet is closed and re-opened', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Build Sheet 1
      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final downloadBtn = find.byKey(const Key('download_surah_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pump();
      await tester.tap(downloadBtn);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(fakeDownloadService.downloadCalls, equals(1));

      // Emit active progress
      fakeDownloadService.emitProgress(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 300000,
        expectedTotalBytes: 1000000,
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('download_progress_bar')), findsOneWidget);

      // Destroy Sheet 1 and build a new Sheet 2 (simulating dismiss and reopen)
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 50));

      // Reopen Sheet
      await tester.pumpWidget(buildTestWidget(surahNumber: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // New Sheet immediately reflects in-flight progress
      final progressBar = find.byKey(const Key('download_progress_bar'));
      await tester.ensureVisible(progressBar);
      await tester.pump();
      expect(progressBar, findsOneWidget);
    });

    test('14. DI Safety: Cubit throws StateError if downloadService is null when download action called', () async {
      final unconfiguredCubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeRepo),
        trackingEngine: trackingEngine,
        audioHandler: handler,
        downloadService: null,
        downloadRepository: null,
      );

      expect(
        () => unconfiguredCubit.startSurahDownload(surahNumber: 1, reciterId: '7'),
        throwsStateError,
      );
      expect(
        () => unconfiguredCubit.pauseSurahDownload(surahNumber: 1, reciterId: '7'),
        throwsStateError,
      );
      expect(
        () => unconfiguredCubit.cancelSurahDownload(surahNumber: 1, reciterId: '7'),
        throwsStateError,
      );
      expect(
        () => unconfiguredCubit.deleteDownloadedSurah(surahNumber: 1, reciterId: '7'),
        throwsStateError,
      );

      await unconfiguredCubit.close();
    });
  });
}
