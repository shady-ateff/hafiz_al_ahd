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
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
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
  SurahAudio? mockSurahAudio;

  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({bool forceRefresh = false}) async {
    return Right([
      AudioReciter(
        id: '7',
        name: 'Mishari Rashid al-`Afasy',
        arabicName: 'مشاري راشد العفاسي',
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
    if (mockSurahAudio != null) {
      return Right(mockSurahAudio!);
    }
    return Right(
      SurahAudio(
        surahNumber: surahNumber,
        reciterId: reciterId,
        audioUrl: 'https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/112.mp3',
        durationMs: 30000,
        ayahTimings: const [],
      ),
    );
  }

  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  }) async {
    return const Right([]);
  }

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(PlaybackPosition position) async {
    return const Right(null);
  }

  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async {
    return const Right(null);
  }
}

class _FakePlayer implements QuranAudioPlayer {
  final StreamController<QuranPlaybackStatus> statusController = StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> posController = StreamController<Duration>.broadcast();
  final StreamController<Duration?> durController = StreamController<Duration?>.broadcast();

  QuranPlaybackStatus _status = QuranPlaybackStatus.idle;
  Duration _pos = Duration.zero;
  Duration? _dur;
  SurahAudio? _track;
  String? lastLoadedLocalFilePath;
  int loadCalls = 0;

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
  AudioRepeatMode get repeatMode => AudioRepeatMode.continuous;

  @override
  int? get repeatCount => null;

  @override
  Stream<QuranPlaybackStatus> get playbackStatusStream => statusController.stream;

  @override
  Stream<Duration> get positionStream => posController.stream;

  @override
  Stream<Duration?> get durationStream => durController.stream;

  @override
  Future<void> loadSurah({required SurahAudio surahAudio, String? localFilePath, Duration? startPosition}) async {
    loadCalls++;
    _track = surahAudio;
    lastLoadedLocalFilePath = localFilePath;
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
  }

  @override
  Future<void> seekTo(Duration position) async {
    _pos = position;
    posController.add(_pos);
  }

  @override
  Future<void> setVolume(double newVolume) async {}

  @override
  Future<void> setRepeatMode(AudioRepeatMode mode, {int? rangeStartAyah, int? rangeEndAyah, int? repeatCount}) async {}

  @override
  Future<void> dispose() async {
    await statusController.close();
    await posController.close();
    await durController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late QuranAudioDatabase db;
  late QuranAudioLocalDataSourceImpl localDataSource;
  late QuranAudioStorageService storageService;
  late AudioDownloadRepositoryImpl downloadRepo;
  late _FakeQuranAudioRepository fakeQuranRepo;
  late _FakePlayer fakePlayer;
  late QuranAudioHandler handler;
  late AyahTrackingEngine trackingEngine;
  late SharedPreferences prefs;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('quran_audio_e2e_');
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

  group('Phase 5.8: End-to-End Runtime Physical Verification & Subsystem Sign-Off', () {
    test('Complete Physical Lifecycle: HTTP Transfer -> Verification -> Promotion -> Local Playback -> Clean Deletion', () async {
      // 1. Prepare simulated binary audio payload with strong cryptographic fingerprint
      final fakeAudioBytes = List.generate(4096, (i) => (i * 7 + 13) % 256);
      final expectedSha256 = sha256.convert(fakeAudioBytes).toString();
      Map<String, String>? capturedHeaders;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        capturedHeaders = request.headers;
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'etag': '"strong-e2e-hash-4096"',
              'content-length': '4096',
              'date': 'Sat, 20 Nov 2026 12:00:05 GMT',
              'last-modified': 'Sat, 20 Nov 2026 12:00:00 GMT',
            },
          );
        }

        return http.StreamedResponse(
          Stream.value(fakeAudioBytes),
          200,
          headers: {
            'etag': '"strong-e2e-hash-4096"',
            'content-length': '4096',
            'date': 'Sat, 20 Nov 2026 12:00:05 GMT',
            'last-modified': 'Sat, 20 Nov 2026 12:00:00 GMT',
          },
        );
      });

      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final cubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeQuranRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeQuranRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeQuranRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeQuranRepo),
        audioHandler: handler,
        trackingEngine: trackingEngine,
        downloadRepository: downloadRepo,
        downloadService: downloadService,
      );

      // STEP A: Initial Pre-Download Verification
      final initialDownloaded = await downloadRepo.isSurahDownloaded(
        surahNumber: 112,
        reciterId: '7',
      );
      expect(initialDownloaded, isFalse);
      expect(await downloadRepo.getLocalAudioPath(surahNumber: 112, reciterId: '7'), isNull);

      // STEP B: Execute Physical Download Pipeline
      final progressEvents = <DownloadProgress>[];
      final completer = Completer<void>();

      final stream = downloadService.downloadSurah(
        surahNumber: 112,
        reciterId: '7',
        audioUrl: 'https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/112.mp3',
        expectedTotalBytes: 4096,
      );

      final sub = stream.listen(
        (p) {
          progressEvents.add(p);
          if (p.isCompleted) completer.complete();
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 10));
      await sub.cancel();

      // STEP C: Representation & Lifecycle Verification
      // Mandatory RFC invariant: Accept-Encoding identity
      expect(capturedHeaders?['Accept-Encoding'], equals('identity'));

      // Lifecycle progression: downloading -> verifying -> completed
      expect(progressEvents.any((p) => p.status == AudioDownloadStatus.downloading), isTrue);
      expect(progressEvents.any((p) => p.status == AudioDownloadStatus.verifying), isTrue);
      expect(progressEvents.last.status, equals(AudioDownloadStatus.completed));
      expect(progressEvents.last.downloadedBytes, equals(4096));

      // STEP D: Physical Storage Verification
      final destFile = await storageService.resolveSurahFile(112, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), equals(4096));

      // Cryptographic integrity proof
      final physicalBytes = await destFile.readAsBytes();
      final physicalSha256 = sha256.convert(physicalBytes).toString();
      expect(physicalSha256, equals(expectedSha256));

      // STEP E: Database & Promotion Journal Invariants
      final record = await localDataSource.getDownloadRecord(112, '7');
      expect(record, isNotNull);
      expect(record!.status, equals(AudioDownloadStatus.completed));
      expect(record.transferIntegrityVerified, isTrue);
      expect(record.actualSizeBytes, equals(4096));
      expect(record.sha256, equals(expectedSha256));
      expect(record.completedAt, isNotNull);

      // Promotion journal must be completely emptied upon successful atomic promotion
      final activeJournal = await localDataSource.getPromotionJournal(112, '7');
      expect(activeJournal, isNull, reason: 'Promotion journal must be deleted after successful promotion');

      // STEP F: Offline Audio Playback Resolution in Cubit
      final localAudioPath = await downloadRepo.getLocalAudioPath(
        surahNumber: 112,
        reciterId: '7',
      );
      expect(localAudioPath, isNotNull);
      expect(localAudioPath, equals(destFile.path));

      // Play Surah through Cubit
      await cubit.playSurah(surahNumber: 112, reciterId: '7');

      // Verify Cubit recognized local offline file and routed localFilePath to AudioHandler
      expect(cubit.state.isLocal, isTrue);
      expect(fakePlayer.loadCalls, equals(1));
      expect(fakePlayer.lastLoadedLocalFilePath, equals(destFile.path));

      // STEP G: Physical Clean Deletion
      final deleteResult = await downloadRepo.deleteDownloadRecord(
        surahNumber: 112,
        reciterId: '7',
      );
      expect(deleteResult.isRight(), isTrue);

      // Assert physical file on disk is removed
      expect(await destFile.exists(), isFalse);

      // Assert database record is deleted
      final postDeleteRecord = await localDataSource.getDownloadRecord(112, '7');
      expect(postDeleteRecord, isNull);

      // Assert repository checks return false/null
      final postDeleteDownloaded = await downloadRepo.isSurahDownloaded(
        surahNumber: 112,
        reciterId: '7',
      );
      expect(postDeleteDownloaded, isFalse);
      expect(await downloadRepo.getLocalAudioPath(surahNumber: 112, reciterId: '7'), isNull);

      await cubit.close();
      downloadService.dispose();
    });

    test('2. Physical Resumption: Interrupted Staging File Resumes with HTTP 206 Partial Content and Promotes Successfully', () async {
      // Create existing partial staging file with 2048 bytes
      final stagingDir = await storageService.getStagingDirectory();
      final stagingFile = File('${stagingDir.path}/dl_7_114.tmp');
      final firstPart = List.generate(2048, (i) => i % 256);
      await stagingFile.writeAsBytes(firstPart);

      final secondPart = List.generate(2048, (i) => (i + 2048) % 256);
      final fullBytes = [...firstPart, ...secondPart];
      final expectedSha256 = sha256.convert(fullBytes).toString();

      String? capturedRange;
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'etag': '"strong-resume-validator-4096"',
              'content-length': '4096',
              'date': 'Sat, 20 Nov 2026 12:00:05 GMT',
              'last-modified': 'Sat, 20 Nov 2026 12:00:00 GMT',
            },
          );
        }

        capturedRange = request.headers['Range'];
        return http.StreamedResponse(
          Stream.value(secondPart),
          206,
          headers: {
            'etag': '"strong-resume-validator-4096"',
            'content-range': 'bytes 2048-4095/4096',
            'content-length': '2048',
            'date': 'Sat, 20 Nov 2026 12:00:05 GMT',
            'last-modified': 'Sat, 20 Nov 2026 12:00:00 GMT',
          },
        );
      });

      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
        clientFactory: () => mockClient,
      );

      final progressEvents = <DownloadProgress>[];
      final completer = Completer<void>();

      final stream = downloadService.downloadSurah(
        surahNumber: 114,
        reciterId: '7',
        audioUrl: 'https://download.quranicaudio.com/quran/mishaari_raashid_al_3afaasee/114.mp3',
        expectedTotalBytes: 4096,
      );

      final sub = stream.listen(
        (p) {
          progressEvents.add(p);
          if (p.isCompleted) completer.complete();
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 10));
      await sub.cancel();

      // Verify HTTP 206 Range Request was properly issued
      expect(capturedRange, equals('bytes=2048-'));

      // Verify physical destination file was promoted and contains all 4096 bytes
      final destFile = await storageService.resolveSurahFile(114, '7');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), equals(4096));

      final physicalBytes = await destFile.readAsBytes();
      expect(sha256.convert(physicalBytes).toString(), equals(expectedSha256));

      // Verify staging file is deleted
      expect(await stagingFile.exists(), isFalse);

      downloadService.dispose();
    });

    test('3. Physical Storage Reconciliation: Self-Healing of Missing Files and Cleanup of Stale Temporary Files', () async {
      // 1. Create an unindexed physical file on disk (Surah 1)
      final surah1File = await storageService.resolveSurahFile(1, '7');
      await surah1File.parent.create(recursive: true);
      await surah1File.writeAsString('audio_content_surah_1');

      // 2. Create a DB record whose physical file is missing (Surah 2)
      final missingRecord = AudioDownload(
        surahNumber: 2,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_002.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 5000,
        sha256: 'missing_hash',
        transferIntegrityVerified: true,
      );
      await downloadRepo.saveDownloadRecord(missingRecord);

      // 3. Create a stale temporary file in staging (> 1 hour old)
      final stagingDir = await storageService.getStagingDirectory();
      final staleTemp = File('${stagingDir.path}/dl_stale_7_003.tmp');
      await staleTemp.writeAsString('stale_temp');
      await staleTemp.setLastModified(DateTime.now().subtract(const Duration(hours: 3)));

      // Execute storage reconciliation via repository
      final result = await downloadRepo.reconcileStorage();
      expect(result.isRight(), isTrue);

      final summary = result.getOrElse(() => throw 'Failed');
      expect(summary.discoveredFiles, equals(1));
      expect(summary.missingFiles, equals(1));
      expect(summary.cleanedTempFiles, equals(1));

      // Verify unindexed file is now indexed in database
      final surah1Record = await localDataSource.getDownloadRecord(1, '7');
      expect(surah1Record, isNotNull);
      expect(surah1Record!.status, equals(AudioDownloadStatus.completed));

      // Verify missing file record was updated to missing status
      final surah2Record = await localDataSource.getDownloadRecord(2, '7');
      expect(surah2Record, isNotNull);
      expect(surah2Record!.status, equals(AudioDownloadStatus.missing));

      // Verify stale temp was deleted
      expect(await staleTemp.exists(), isFalse);
    });

    test('4. User Scenario 3: Pausing download, closing dialog, reopening restores Paused status and resumes cleanly', () async {
      // Create a paused record in database with 1024 bytes
      final pausedRecord = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.paused,
        actualSizeBytes: 1024,
        expectedSizeBytes: 4096,
      );
      await downloadRepo.saveDownloadRecord(pausedRecord);

      final cubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeQuranRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeQuranRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeQuranRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeQuranRepo),
        audioHandler: handler,
        trackingEngine: trackingEngine,
        downloadRepository: downloadRepo,
      );

      // Verify that checking status (simulating opening dialog) restores paused state
      await cubit.checkDownloadStatus(surahNumber: 1, reciterId: '7');

      final displayStatus = cubit.state.getDownloadDisplayStatus(1, '7');
      expect(displayStatus, equals(AudioDownloadDisplayStatus.paused));

      final progress = cubit.state.getDownloadProgress(1, '7');
      expect(progress, isNotNull);
      expect(progress!.status, equals(AudioDownloadStatus.paused));
      expect(progress.downloadedBytes, equals(1024));
      expect(progress.expectedTotalBytes, equals(4096));

      await cubit.close();
    });

    test('5. User Scenario 1 & 2: Cancelling download purges staging file, resets DB, resets state, and starts from byte 0 with instant feedback', () async {
      // 1. Create a staging file with partial data
      final stagingDir = await storageService.getStagingDirectory();
      final stagingFile = File('${stagingDir.path}/dl_7_001.tmp');
      await stagingFile.writeAsBytes(List.generate(500, (i) => i % 256));
      expect(await stagingFile.exists(), isTrue);

      final record = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 500,
      );
      await downloadRepo.saveDownloadRecord(record);

      final downloadService = QuranAudioDownloadService(
        localDataSource: localDataSource,
        storageService: storageService,
      );

      final cubit = QuranAudioCubit(
        getRecitersUseCase: GetRecitersUseCase(fakeQuranRepo),
        getSurahAudioUseCase: GetSurahAudioUseCase(fakeQuranRepo),
        getPlaybackPositionUseCase: GetPlaybackPositionUseCase(fakeQuranRepo),
        savePlaybackPositionUseCase: SavePlaybackPositionUseCase(fakeQuranRepo),
        audioHandler: handler,
        trackingEngine: trackingEngine,
        downloadRepository: downloadRepo,
        downloadService: downloadService,
      );

      // Cancel the download
      await cubit.cancelSurahDownload(surahNumber: 1, reciterId: '7');

      // Assert physical staging file is deleted!
      expect(await stagingFile.exists(), isFalse);

      // Assert database record reflects cancelled with 0 bytes
      final dbRecord = await localDataSource.getDownloadRecord(1, '7');
      expect(dbRecord, isNotNull);
      expect(dbRecord!.status, equals(AudioDownloadStatus.cancelled));
      expect(dbRecord.actualSizeBytes, equals(0));

      // Assert UI display status is reset to notDownloaded
      expect(cubit.state.getDownloadDisplayStatus(1, '7'), equals(AudioDownloadDisplayStatus.notDownloaded));

      // Instant feedback check: Calling startSurahDownload immediately emits downloading status
      final startFuture = cubit.startSurahDownload(surahNumber: 1, reciterId: '7');
      expect(cubit.state.getDownloadDisplayStatus(1, '7'), equals(AudioDownloadDisplayStatus.downloading));
      await startFuture;

      await cubit.close();
      downloadService.dispose();
    });
  });
}
