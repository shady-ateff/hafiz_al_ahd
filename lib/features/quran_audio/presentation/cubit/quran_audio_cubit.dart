import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bloc/bloc.dart';
import '../../core/audio/quran_audio_handler.dart';
import '../../core/audio/quran_audio_player.dart';
import '../../core/tracking/ayah_tracking_engine.dart';
import '../../data/services/quran_audio_download_service.dart';
import '../../data/services/quran_audio_queue_service.dart';
import '../../data/services/quran_download_notification_manager.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/audio_highlight_state.dart';
import '../../domain/entities/audio_reciter.dart';
import '../../domain/entities/ayah_timing.dart';
import '../../domain/entities/download_progress.dart';
import '../../domain/entities/playback_position.dart';
import '../../domain/entities/quran_download_queue_progress.dart';
import '../../domain/entities/storage_preflight_result.dart';
import '../../domain/errors/quran_audio_failures.dart';
import '../../domain/repositories/base_audio_download_repository.dart';
import '../../domain/usecases/get_playback_position_use_case.dart';
import '../../domain/usecases/get_reciters_use_case.dart';
import '../../domain/usecases/get_surah_audio_use_case.dart';
import '../../domain/usecases/save_playback_position_use_case.dart';
import '../../../quran/domain/entities/ayah_id.dart';
import 'quran_audio_state.dart';

/// Cubit managing the Quran Audio presentation state, Ayah tracking highlights,
/// reciter selection, and UI-level playback dispatching.
///
/// **ARCHITECTURAL GUARANTEES**:
/// - Strictly decoupled from manual Mushaf text selection (`QuranCubit.selectedAyahId`).
/// - Presentation layer communicates EXCLUSIVELY with [QuranAudioHandler].
/// - Lifecycle-safe: Ephemeral Cubit lifecycles never dispose or interrupt background playback.
/// - Immediate Reconnection: Reconnects seamlessly to ongoing background playback and
///   instantly restores the active Ayah highlight upon instantiation.
class QuranAudioCubit extends Cubit<QuranAudioState> {
  final GetRecitersUseCase getRecitersUseCase;
  final GetSurahAudioUseCase getSurahAudioUseCase;
  final QuranAudioHandler audioHandler;
  final AyahTrackingEngine trackingEngine;
  final SavePlaybackPositionUseCase savePlaybackPositionUseCase;
  final GetPlaybackPositionUseCase getPlaybackPositionUseCase;
  final BaseQuranAudioDownloadService? downloadService;
  final BaseAudioDownloadRepository? downloadRepository;
  final QuranAudioQueueService? queueService;
  final QuranDownloadNotificationManager? notificationManager;

  final Map<String, StreamSubscription<DownloadProgress>> _downloadSubs = {};

  StreamSubscription<QuranPlaybackStatus>? _statusSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<QuranDownloadQueueProgress>? _queueProgressSub;

  QuranAudioCubit({
    required this.getRecitersUseCase,
    required this.getSurahAudioUseCase,
    required this.audioHandler,
    required this.trackingEngine,
    required this.savePlaybackPositionUseCase,
    required this.getPlaybackPositionUseCase,
    this.downloadService,
    this.downloadRepository,
    this.queueService,
    this.notificationManager,
  }) : super(QuranAudioState(
          reciters: AudioReciter.kDefaultReciters,
          selectedReciter: AudioReciter.kDefaultReciter,
        )) {
    // 1. Snapshot existing background state FIRST
    _reconnectToOngoingAudio();
    // 2. Subscribe to active event streams SECOND so subsequent updates are seamlessly processed
    _initHandlerSubscriptions();
    _initQueueSubscription();
  }

  void _initQueueSubscription() {
    if (queueService != null) {
      if (queueService!.currentProgress != null) {
        emit(state.copyWith(fullQuranProgress: queueService!.currentProgress));
      }
      _queueProgressSub = queueService!.progressStream.listen((p) {
        emit(state.copyWith(fullQuranProgress: p));
        if (p.isCompleted) {
          final updatedSet = Set<String>.from(state.downloadedReciterIds)..add(p.reciterId);
          emit(state.copyWith(
            downloadedReciterIds: updatedSet,
            isFullQuranDownloaded: state.selectedReciter?.id == p.reciterId ? true : state.isFullQuranDownloaded,
          ));
        }
      });
    }
  }

  void _reconnectToOngoingAudio() {
    final track = audioHandler.currentTrack;
    if (track != null) {
      trackingEngine.setTimings(track.ayahTimings);
      final pos = audioHandler.currentPosition;
      final resolvedTiming = trackingEngine.resolveAyahAtPosition(pos.inMilliseconds);
      final activeAyah = resolvedTiming != null
          ? AyahId(surahNumber: resolvedTiming.surahNumber, ayahNumber: resolvedTiming.ayahNumber)
          : null;

      final isPlaying = audioHandler.status == QuranPlaybackStatus.playing;
      final isBuffering = audioHandler.status == QuranPlaybackStatus.buffering;

      // Extract ongoing reciter if available from mediaItem or track metadata
      final ongoingReciterName = audioHandler.mediaItem.value?.artist ?? track.reciterId;
      final reciter = AudioReciter(
        id: track.reciterId,
        name: ongoingReciterName,
        arabicName: ongoingReciterName,
        availableFormat: track.format,
      );

      emit(state.copyWith(
        currentSurahNumber: track.surahNumber,
        currentSurahAudio: track,
        selectedReciter: reciter,
        currentPosition: pos,
        totalDuration: audioHandler.duration ?? Duration(milliseconds: track.durationMs),
        playbackStatus: audioHandler.status,
        highlightState: state.highlightState.copyWith(
          isPlaying: isPlaying,
          isBuffering: isBuffering,
          activeAyah: activeAyah,
          clearActiveAyah: activeAyah == null,
        ),
      ));
    }
  }

  void _initHandlerSubscriptions() {
    _statusSub = audioHandler.playbackStatusStream.listen((status) {
      final isPlaying = status == QuranPlaybackStatus.playing;
      final isBuffering = status == QuranPlaybackStatus.buffering;

      final updatedHighlight = state.highlightState.copyWith(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
      );

      emit(state.copyWith(
        playbackStatus: status,
        highlightState: updatedHighlight,
      ));

      if (status == QuranPlaybackStatus.completed) {
        _handlePlaybackCompleted();
      }
    });

    _positionSub = audioHandler.positionStream.listen((position) {
      _handlePositionUpdate(position);
    });

    _durationSub = audioHandler.durationStream.listen((duration) {
      if (duration != null) {
        emit(state.copyWith(totalDuration: duration));
      }
    });

    // Synchronize UI if track changes externally (e.g. from lockscreen or headset skip next/previous)
    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (item != null) {
        final surahNum = item.extras?['surahNumber'] as int?;
        if (surahNum != null && surahNum != state.currentSurahNumber) {
          final track = audioHandler.currentTrack;
          final isPlaying = audioHandler.status == QuranPlaybackStatus.playing ||
              audioHandler.isActuallyPlaying;
          final isBuffering = audioHandler.status == QuranPlaybackStatus.buffering;

          if (track != null && track.surahNumber == surahNum) {
            trackingEngine.setTimings(track.ayahTimings);
            emit(state.copyWith(
              currentSurahNumber: surahNum,
              currentSurahAudio: track,
              totalDuration: Duration(milliseconds: track.durationMs),
              playbackStatus: isPlaying
                  ? QuranPlaybackStatus.playing
                  : (isBuffering ? QuranPlaybackStatus.buffering : audioHandler.status),
              highlightState: state.highlightState.copyWith(
                clearActiveAyah: true,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              ),
            ));
          } else {
            emit(state.copyWith(
              currentSurahNumber: surahNum,
              playbackStatus: isPlaying
                  ? QuranPlaybackStatus.playing
                  : (isBuffering ? QuranPlaybackStatus.buffering : audioHandler.status),
              highlightState: state.highlightState.copyWith(
                clearActiveAyah: true,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              ),
            ));
          }
        }
      }
    });
  }

  void _handlePositionUpdate(Duration position) {
    final surahNum = state.currentSurahNumber;
    if (surahNum == null) {
      emit(state.copyWith(currentPosition: position));
      return;
    }

    final isPlaying = audioHandler.status == QuranPlaybackStatus.playing ||
        audioHandler.isActuallyPlaying;

    // Resolve active Ayah using binary search
    final resolvedTiming = trackingEngine.resolveAyahAtPosition(position.inMilliseconds);

    AyahId? activeAyah;
    if (resolvedTiming != null) {
      activeAyah = AyahId(
        surahNumber: resolvedTiming.surahNumber,
        ayahNumber: resolvedTiming.ayahNumber,
      );
      audioHandler.setActiveAyahTiming(resolvedTiming);
    }

    final updatedHighlight = state.highlightState.copyWith(
      activeAyah: activeAyah,
      clearActiveAyah: activeAyah == null,
      isPlaying: isPlaying ? true : null,
    );

    emit(state.copyWith(
      currentPosition: position,
      playbackStatus: (isPlaying && !state.isPlaying)
          ? QuranPlaybackStatus.playing
          : state.playbackStatus,
      highlightState: updatedHighlight,
    ));
  }

  void _handlePlaybackCompleted() {
    _savePosition();
    if (state.highlightState.repeatMode == AudioRepeatMode.continuous &&
        (state.currentSurahNumber ?? 0) < 114) {
      emit(state.copyWith(
        playbackStatus: QuranPlaybackStatus.loading,
        highlightState: state.highlightState.copyWith(
          clearActiveAyah: true,
          isPlaying: true,
        ),
      ));
      return;
    }

    if (state.highlightState.repeatMode == AudioRepeatMode.surah) {
      // AudioHandler manages Surah repetition: if repeating, seek(0) & play()
      // will emit playing; if all iterations completed, handler calls stop().
      return;
    }

    stop();
  }

  Future<void>? _initFuture;

  /// Initializes the audio subsystem: loads reciters and restores last playback position.
  /// Guarded by in-flight Future to safely serialize concurrent invocations.
  Future<void> init() {
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _performInit();
    return _initFuture!;
  }

  Future<void> _performInit() async {
    emit(state.copyWith(isLoadingReciters: true, clearErrorMessage: true));

    AudioReciter? chosenReciter;
    try {
      final recitersResult = await getRecitersUseCase();

      await recitersResult.fold(
        (failure) async {
          final fallbackList = state.reciters.isNotEmpty
              ? state.reciters
              : AudioReciter.kDefaultReciters;
          emit(state.copyWith(
            isLoadingReciters: false,
            reciters: fallbackList,
            selectedReciter: state.selectedReciter ?? AudioReciter.kDefaultReciter,
            errorMessage: failure.message,
            isOfflineError: failure is QuranAudioNetworkFailure,
          ));
        },
        (reciters) async {
          if (reciters.isNotEmpty) {
            final ongoingReciterId = state.currentSurahAudio?.reciterId;
            if (ongoingReciterId != null) {
              for (final r in reciters) {
                if (r.id == ongoingReciterId) {
                  chosenReciter = r;
                  break;
                }
              }
            }
            if (chosenReciter == null) {
              for (final r in reciters) {
                if (r.id == '7') {
                  chosenReciter = r;
                  break;
                }
              }
            }
            chosenReciter ??= reciters.first;
          }
          emit(state.copyWith(
            isLoadingReciters: false,
            reciters: reciters,
            selectedReciter: chosenReciter,
          ));
        },
      );
    } catch (e) {
      final fallbackList = state.reciters.isNotEmpty
          ? state.reciters
          : AudioReciter.kDefaultReciters;
      emit(state.copyWith(
        isLoadingReciters: false,
        reciters: fallbackList,
        selectedReciter: state.selectedReciter ?? AudioReciter.kDefaultReciter,
        errorMessage: 'فشل تحميل القراء: $e',
      ));
    } finally {
      _initFuture = null;
    }

    // Only restore from database if there is NO actively playing / loaded track
    if (state.currentSurahNumber == null) {
      final positionResult = await getPlaybackPositionUseCase();
      positionResult.fold(
        (_) {
          emit(state.copyWith(
            selectedReciter: chosenReciter ?? state.selectedReciter ?? AudioReciter.kDefaultReciter,
          ));
        },
        (lastPos) {
          if (lastPos != null && state.reciters.isNotEmpty) {
            AudioReciter? matchedReciter;
            for (final r in state.reciters) {
              if (r.id == lastPos.reciterId) {
                matchedReciter = r;
                break;
              }
            }
            matchedReciter ??= chosenReciter ?? state.selectedReciter ?? AudioReciter.kDefaultReciter;

            emit(state.copyWith(
              selectedReciter: matchedReciter,
              currentSurahNumber: lastPos.surahNumber,
              currentPosition: Duration(milliseconds: lastPos.positionMs),
              totalDuration: Duration(milliseconds: lastPos.durationMs ?? 0),
              highlightState: state.highlightState.copyWith(
                activeAyah: AyahId(
                  surahNumber: lastPos.surahNumber,
                  ayahNumber: lastPos.currentAyahNumber,
                ),
              ),
            ));
          } else {
            // First time ever: no saved position exists
            // Leave currentSurahNumber as null so fallbackSurahNumber from visible page resolves dynamically
            emit(state.copyWith(
              selectedReciter: chosenReciter ?? state.selectedReciter ?? AudioReciter.kDefaultReciter,
            ));
          }
        },
      );
    }

    await checkAllDownloadedReciters();
  }

  /// Selects an active reciter for playback.
  void selectReciter(String reciterId) {
    if (state.selectedReciter?.id == reciterId) return;

    AudioReciter? reciter;
    for (final r in state.reciters) {
      if (r.id == reciterId) {
        reciter = r;
        break;
      }
    }

    if (reciter != null) {
      trackingEngine.reset();
      final isFull = state.downloadedReciterIds.contains(reciter.id);
      emit(state.copyWith(
        selectedReciter: reciter,
        isFullQuranDownloaded: isFull,
        highlightState: state.highlightState.copyWith(clearActiveAyah: true),
      ));
      checkFullQuranStatus(reciter.id);

      if (state.currentSurahNumber != null && (state.isPlaying || state.isPaused)) {
        playSurah(surahNumber: state.currentSurahNumber!, reciterId: reciter.id);
      }
    }
  }

  /// Streams a complete Surah over the network from Quran Foundation.
  Future<void> playSurah({
    required int surahNumber,
    String? reciterId,
    Duration? startPosition,
    int? startAyahNumber,
  }) async {
    final activeReciter = state.selectedReciter ?? AudioReciter.kDefaultReciter;
    final activeReciterId = reciterId ?? activeReciter.id;

    emit(state.copyWith(
      isLoadingAudio: true,
      currentSurahNumber: surahNumber,
      selectedReciter: activeReciter,
      clearErrorMessage: true,
    ));

    final audioResult = await getSurahAudioUseCase(
      surahNumber: surahNumber,
      reciterId: activeReciterId,
    );

    await audioResult.fold(
      (failure) async {
        emit(state.copyWith(
          isLoadingAudio: false,
          playbackStatus: QuranPlaybackStatus.error,
          errorMessage: failure.message,
          isOfflineError: failure is QuranAudioNetworkFailure,
        ));
      },
      (surahAudio) async {
        trackingEngine.setTimings(surahAudio.ayahTimings);

        Duration? initialPos = startPosition;
        if (startAyahNumber != null) {
          AyahTiming? timing;
          for (final t in surahAudio.ayahTimings) {
            if (t.ayahNumber == startAyahNumber) {
              timing = t;
              break;
            }
          }
          if (timing != null) {
            initialPos = Duration(milliseconds: timing.timestampFrom);
          }
        }

        String? localPath;
        if (downloadRepository != null) {
          try {
            localPath = await downloadRepository!.getLocalAudioPath(
              surahNumber: surahNumber,
              reciterId: activeReciterId,
            );
          } catch (_) {}
        }

        emit(state.copyWith(
          isLoadingAudio: false,
          currentSurahAudio: surahAudio,
          isLocal: localPath != null,
          totalDuration: Duration(milliseconds: surahAudio.durationMs),
        ));

        // Delegate entire load, media notification, and playback start to AudioHandler
        await audioHandler.playSurah(
          surahAudio: surahAudio,
          reciterName: state.selectedReciter?.arabicName ??
              state.selectedReciter?.name ??
              'القرآن الكريم',
          localFilePath: localPath,
          startPosition: initialPos,
        );

        emit(state.copyWith(
          playbackStatus: audioHandler.status,
          highlightState: state.highlightState.copyWith(
            isPlaying: audioHandler.status == QuranPlaybackStatus.playing || audioHandler.isActuallyPlaying,
          ),
        ));

        if (initialPos != null) {
          _handlePositionUpdate(initialPos);
        }
      },
    );
  }

  /// Plays a specific [ayahId] directly by seeking if current surah matches,
  /// or loading the surah and starting directly at the ayah.
  Future<void> playAyah(AyahId ayahId) async {
    if (state.currentSurahAudio?.surahNumber == ayahId.surahNumber) {
      await seekToAyah(ayahId.ayahNumber);
      if (!state.isPlaying) {
        await resume();
      }
    } else {
      await playSurah(
        surahNumber: ayahId.surahNumber,
        startAyahNumber: ayahId.ayahNumber,
      );
    }
  }

  /// Toggles between Play and Pause based on active playback status.
  /// If playback has not started yet or no track is loaded, starts playing
  /// [fallbackSurahNumber] (or current surah, or Surah 1) optionally starting at [fallbackStartAyahNumber].
  Future<void> togglePlayPause({
    int? fallbackSurahNumber,
    int? fallbackStartAyahNumber,
  }) async {
    final isActuallyPlaying =
        state.isPlaying ||
        audioHandler.status == QuranPlaybackStatus.playing ||
        audioHandler.isActuallyPlaying ||
        (state.currentPosition > Duration.zero &&
            !state.isPaused &&
            audioHandler.status != QuranPlaybackStatus.paused);

    if (isActuallyPlaying) {
      await pause();
    } else if ((state.isPaused || audioHandler.status == QuranPlaybackStatus.paused) &&
        (state.currentSurahAudio != null || audioHandler.currentTrack != null)) {
      if (fallbackSurahNumber != null &&
          state.currentSurahNumber != null &&
          fallbackSurahNumber != state.currentSurahNumber) {
        await playSurah(
          surahNumber: fallbackSurahNumber,
          startAyahNumber: fallbackStartAyahNumber,
        );
      } else {
        await resume();
      }
    } else {
      // Stopped, idle, completed, or fresh start:
      // Prioritize visible page Surah first, then saved state, then Surah 1
      final surahToPlay = fallbackSurahNumber ?? state.currentSurahNumber ?? 1;
      await playSurah(
        surahNumber: surahToPlay,
        startAyahNumber: fallbackStartAyahNumber,
      );
    }
  }

  /// Resumes playback via AudioHandler.
  Future<void> resume() async {
    await audioHandler.play();
  }

  /// Pauses active playback via AudioHandler and persists position.
  Future<void> pause() async {
    await audioHandler.pause();
    _savePosition();
  }

  /// Stops playback via AudioHandler, clears tracking, and persists position.
  Future<void> stop() async {
    _savePosition();
    await audioHandler.stop();
    trackingEngine.reset();
    final clearedHighlight = state.highlightState.copyWith(
      clearActiveAyah: true,
      isPlaying: false,
      isBuffering: false,
    );
    emit(state.copyWith(
      currentPosition: Duration.zero,
      playbackStatus: QuranPlaybackStatus.idle,
      highlightState: clearedHighlight,
      clearTrack: true,
    ));
  }

  /// Seeks to a specific [position] via AudioHandler.
  Future<void> seekTo(Duration position) async {
    await audioHandler.seek(position);
    _handlePositionUpdate(position);
  }

  /// Seeks playback to the beginning of a specific [ayahNumber] via AudioHandler.
  Future<void> seekToAyah(int ayahNumber) async {
    final audio = state.currentSurahAudio;
    if (audio == null) return;

    AyahTiming? timing;
    for (final t in audio.ayahTimings) {
      if (t.ayahNumber == ayahNumber) {
        timing = t;
        break;
      }
    }

    if (timing != null) {
      final targetDuration = Duration(milliseconds: timing.timestampFrom);
      await audioHandler.seek(targetDuration);
      _handlePositionUpdate(targetDuration);
    }
  }

  /// Advances to next Surah.
  Future<void> playNextSurah() async {
    final currentSurah = state.currentSurahNumber ?? audioHandler.currentTrack?.surahNumber;
    if (currentSurah != null && currentSurah < 114) {
      await playSurah(surahNumber: currentSurah + 1);
    } else {
      await audioHandler.skipToNext();
    }
  }

  /// Rewinds to previous Surah.
  Future<void> playPreviousSurah() async {
    final currentSurah = state.currentSurahNumber ?? audioHandler.currentTrack?.surahNumber;
    if (currentSurah != null && currentSurah > 1) {
      await playSurah(surahNumber: currentSurah - 1);
    } else {
      await audioHandler.skipToPrevious();
    }
  }

  /// Configures Ayah repetition mode via AudioHandler.
  Future<void> setRepeatMode(
    AudioRepeatMode mode, {
    int? rangeStartAyah,
    int? rangeEndAyah,
    int? repeatCount,
  }) async {
    await audioHandler.setQuranRepeatMode(
      mode,
      rangeStartAyah: rangeStartAyah,
      rangeEndAyah: rangeEndAyah,
      repeatCount: repeatCount,
    );

    AyahId? startId;
    AyahId? endId;
    final surah = state.currentSurahNumber ?? 1;

    if (rangeStartAyah != null) {
      startId = AyahId(surahNumber: surah, ayahNumber: rangeStartAyah);
    }
    if (rangeEndAyah != null) {
      endId = AyahId(surahNumber: surah, ayahNumber: rangeEndAyah);
    }

    final updatedHighlight = state.highlightState.copyWith(
      repeatMode: mode,
      repeatRangeStart: startId,
      clearRangeStart: startId == null,
      repeatRangeEnd: endId,
      clearRangeEnd: endId == null,
      repeatCount: repeatCount,
      clearRepeatCount: repeatCount == null,
    );

    emit(state.copyWith(highlightState: updatedHighlight));
  }

  void _savePosition() {
    final surah = state.currentSurahNumber;
    final reciter = state.selectedReciter;
    if (surah == null || reciter == null) return;

    final currentAyah = state.highlightState.activeAyah?.ayahNumber ?? 1;

    savePlaybackPositionUseCase(PlaybackPosition(
      reciterId: reciter.id,
      surahNumber: surah,
      positionMs: state.currentPosition.inMilliseconds,
      currentAyahNumber: currentAyah,
      durationMs: state.totalDuration.inMilliseconds,
    ));
  }

  // -------------------------------------------------------------
  // Single-Surah Audio Download Management (QA.5 Phase 5.5)
  // -------------------------------------------------------------

  /// Checks and refreshes the download status for a given [surahNumber] and [reciterId].
  Future<void> checkDownloadStatus({
    required int surahNumber,
    required String reciterId,
  }) async {
    final key = '$reciterId:$surahNumber';

    // 1. If download service has an active in-flight task, prioritize it
    final active = downloadService?.getProgress(surahNumber, reciterId);
    if (active != null) {
      final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = active;
      emit(state.copyWith(downloadProgressMap: map));

      if (!_downloadSubs.containsKey(key)) {
        _downloadSubs[key] = downloadService!.watchProgress(surahNumber, reciterId).listen((p) {
          final m = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = p;
          emit(state.copyWith(downloadProgressMap: m));
        });
      }
      return;
    }

    // 2. Query repository for existing record in database
    if (downloadRepository != null) {
      final record = await downloadRepository!.getDownloadRecord(
        surahNumber: surahNumber,
        reciterId: reciterId,
      );

      final map = Map<String, DownloadProgress>.from(state.downloadProgressMap);
      if (record != null) {
        if (record.status == AudioDownloadStatus.completed) {
          final isDownloaded = await downloadRepository!.isSurahDownloaded(
            surahNumber: surahNumber,
            reciterId: reciterId,
          );
          if (isDownloaded) {
            map[key] = DownloadProgress(
              surahNumber: surahNumber,
              reciterId: reciterId,
              status: AudioDownloadStatus.completed,
              downloadedBytes: record.actualSizeBytes,
              expectedTotalBytes: record.expectedSizeBytes,
            );
          } else {
            map.remove(key);
          }
        } else if (record.status == AudioDownloadStatus.paused) {
          map[key] = DownloadProgress(
            surahNumber: surahNumber,
            reciterId: reciterId,
            status: AudioDownloadStatus.paused,
            downloadedBytes: record.actualSizeBytes,
            expectedTotalBytes: record.expectedSizeBytes,
          );
        } else if (record.status == AudioDownloadStatus.failed) {
          map[key] = DownloadProgress(
            surahNumber: surahNumber,
            reciterId: reciterId,
            status: AudioDownloadStatus.failed,
            downloadedBytes: record.actualSizeBytes,
            expectedTotalBytes: record.expectedSizeBytes,
            lastError: record.lastError,
          );
        } else if (record.status == AudioDownloadStatus.downloading) {
          map[key] = DownloadProgress(
            surahNumber: surahNumber,
            reciterId: reciterId,
            status: AudioDownloadStatus.paused,
            downloadedBytes: record.actualSizeBytes,
            expectedTotalBytes: record.expectedSizeBytes,
          );
        } else {
          map.remove(key);
        }
      } else {
        final isDownloaded = await downloadRepository!.isSurahDownloaded(
          surahNumber: surahNumber,
          reciterId: reciterId,
        );
        if (isDownloaded) {
          map[key] = DownloadProgress(
            surahNumber: surahNumber,
            reciterId: reciterId,
            status: AudioDownloadStatus.completed,
            downloadedBytes: 0,
          );
        } else {
          map.remove(key);
        }
      }
      emit(state.copyWith(downloadProgressMap: map));
    }
  }

  /// Initiates download of an individual Surah track for offline storage.
  Future<void> startSurahDownload({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (downloadService == null) {
      throw StateError(
        'BaseQuranAudioDownloadService is required for download operations.',
      );
    }
    final key = '$reciterId:$surahNumber';

    final existing = state.downloadProgressMap[key];
    if (existing != null && existing.status == AudioDownloadStatus.downloading) {
      return;
    }

    _downloadSubs[key]?.cancel();
    _downloadSubs.remove(key);

    // Instant UI feedback: Emit downloading state immediately
    final initialProgress = DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.downloading,
      downloadedBytes: existing?.downloadedBytes ?? 0,
      expectedTotalBytes: existing?.expectedTotalBytes,
    );
    final initialMap = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = initialProgress;
    emit(state.copyWith(downloadProgressMap: initialMap));

    final result = await getSurahAudioUseCase(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );

    await result.fold(
      (failure) async {
        final progress = DownloadProgress(
          surahNumber: surahNumber,
          reciterId: reciterId,
          status: AudioDownloadStatus.failed,
          downloadedBytes: 0,
          lastError: failure.message,
        );
        final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = progress;
        emit(state.copyWith(downloadProgressMap: map));
      },
      (surahAudio) async {
        _downloadSubs[key]?.cancel();

        final stream = downloadService!.downloadSurah(
          surahNumber: surahNumber,
          reciterId: reciterId,
          audioUrl: surahAudio.audioUrl,
        );

        notificationManager?.trackSingleSurahDownload(
          surahNumber: surahNumber,
          reciterId: reciterId,
          reciterName: state.selectedReciter?.displayName,
          progressStream: stream,
        );

        _downloadSubs[key] = stream.listen((progress) {
          final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = progress;
          emit(state.copyWith(downloadProgressMap: map));
        });
      },
    );
  }

  /// Pauses an active Surah download.
  Future<void> pauseSurahDownload({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (downloadService == null) {
      throw StateError(
        'BaseQuranAudioDownloadService is required for download operations.',
      );
    }
    final key = '$reciterId:$surahNumber';
    _downloadSubs[key]?.cancel();
    _downloadSubs.remove(key);

    await downloadService!.pauseDownload(surahNumber, reciterId);

    final current = state.downloadProgressMap[key];
    final serviceProgress = downloadService!.getProgress(surahNumber, reciterId);
    final pausedProgress = serviceProgress ?? DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.paused,
      downloadedBytes: current?.downloadedBytes ?? 0,
      expectedTotalBytes: current?.expectedTotalBytes,
    );
    final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..[key] = pausedProgress;
    emit(state.copyWith(downloadProgressMap: map));
  }

  /// Cancels an in-flight Surah download and stops tracking.
  Future<void> cancelSurahDownload({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (downloadService == null) {
      throw StateError(
        'BaseQuranAudioDownloadService is required for download operations.',
      );
    }
    final key = '$reciterId:$surahNumber';
    _downloadSubs[key]?.cancel();
    _downloadSubs.remove(key);
    await downloadService!.cancelDownload(surahNumber, reciterId);
    await notificationManager?.cancelSingleSurahSession();

    // Immediately remove from state map so UI transitions to notDownloaded
    final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..remove(key);
    emit(state.copyWith(downloadProgressMap: map));
  }

  /// Retries a failed or paused Surah download.
  Future<void> retrySurahDownload({
    required int surahNumber,
    required String reciterId,
  }) async {
    await startSurahDownload(surahNumber: surahNumber, reciterId: reciterId);
  }

  /// Deletes a verified downloaded Surah and removes its record.
  Future<void> deleteDownloadedSurah({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (downloadRepository == null) {
      throw StateError(
        'BaseAudioDownloadRepository is required for delete operations.',
      );
    }
    await downloadRepository!.deleteDownloadRecord(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );
    final key = '$reciterId:$surahNumber';
    final map = Map<String, DownloadProgress>.from(state.downloadProgressMap)..remove(key);
    emit(state.copyWith(downloadProgressMap: map));
  }

  // ---------------------------------------------------------------------------
  // Full-Quran Audio Download Management (QA.6 Phase 6.7)
  // ---------------------------------------------------------------------------

  /// Checks whether all 114 Surahs for [reciterId] are verified downloaded on disk.
  Future<void> checkFullQuranStatus(String reciterId) async {
    if (downloadRepository != null) {
      final records = await downloadRepository!.getDownloadedSurahs(reciterId: reciterId);
      final isFull = records.length >= 114;
      final updatedSet = Set<String>.from(state.downloadedReciterIds);
      if (isFull) {
        updatedSet.add(reciterId);
      } else {
        updatedSet.remove(reciterId);
      }
      emit(state.copyWith(
        isFullQuranDownloaded: isFull,
        downloadedReciterIds: updatedSet,
      ));
    }
  }

  /// Checks all reciters to identify which ones have complete 114-surah offline libraries.
  Future<void> checkAllDownloadedReciters() async {
    if (downloadRepository != null) {
      final allRecords = await downloadRepository!.getAllDownloadedRecords();
      final countMap = <String, int>{};
      for (final rec in allRecords) {
        if (rec.isPlayable) {
          countMap[rec.reciterId] = (countMap[rec.reciterId] ?? 0) + 1;
        }
      }
      final completedReciters = <String>{};
      countMap.forEach((reciterId, count) {
        if (count >= 114) {
          completedReciters.add(reciterId);
        }
      });
      emit(state.copyWith(
        downloadedReciterIds: completedReciters,
        isFullQuranDownloaded: state.selectedReciter != null && completedReciters.contains(state.selectedReciter!.id),
      ));
    }
  }

  /// Checks storage preflight before full-Quran download.
  Future<StoragePreflightResult?> checkFullQuranPreflight({
    required String reciterId,
    List<int?>? expectedSurahSizes,
  }) async {
    return await queueService?.checkStoragePreflight(
      reciterId: reciterId,
      expectedSurahSizes: expectedSurahSizes,
    );
  }

  /// Starts full-Quran sequential download queue for [reciterId].
  Future<void> startFullQuranDownload({
    required String reciterId,
    FutureOr<String> Function(int surahNumber)? urlBuilder,
    List<int>? expectedSurahSizes,
  }) async {
    if (queueService == null) {
      throw StateError('QuranAudioQueueService is required for full Quran download.');
    }

    final effectiveUrlBuilder = urlBuilder ?? (surahNum) async {
      final res = await getSurahAudioUseCase(surahNumber: surahNum, reciterId: reciterId);
      return res.fold((_) => '', (audio) => audio.audioUrl);
    };

    await queueService!.startQueue(
      reciterId: reciterId,
      urlBuilder: effectiveUrlBuilder,
      expectedSurahSizes: expectedSurahSizes,
    );
  }

  /// Pauses active full-Quran download queue.
  Future<void> pauseFullQuranDownload(String queueId) async {
    await queueService?.pauseQueue(queueId);
  }

  /// Resumes paused full-Quran download queue.
  Future<void> resumeFullQuranDownload({
    required String queueId,
    required String reciterId,
    FutureOr<String> Function(int surahNumber)? urlBuilder,
  }) async {
    final effectiveUrlBuilder = urlBuilder ?? (surahNum) async {
      final res = await getSurahAudioUseCase(surahNumber: surahNum, reciterId: reciterId);
      return res.fold((_) => '', (audio) => audio.audioUrl);
    };
    await queueService?.resumeQueue(
      queueId: queueId,
      urlBuilder: effectiveUrlBuilder,
    );
  }

  /// Cancels full-Quran download queue.
  Future<void> cancelFullQuranDownload(String queueId) async {
    await queueService?.cancelQueue(queueId);
    await notificationManager?.cancelQueueSession();
  }

  /// Retries failed items in full-Quran download queue.
  Future<void> retryFullQuranDownload({
    required String queueId,
    required String reciterId,
    FutureOr<String> Function(int surahNumber)? urlBuilder,
  }) async {
    final effectiveUrlBuilder = urlBuilder ?? (surahNum) async {
      final res = await getSurahAudioUseCase(surahNumber: surahNum, reciterId: reciterId);
      return res.fold((_) => '', (audio) => audio.audioUrl);
    };
    await queueService?.retryQueue(
      queueId: queueId,
      urlBuilder: effectiveUrlBuilder,
    );
  }

  @override
  Future<void> close() async {
    // 1. Persist current listening position
    _savePosition();

    // 2. Cancel Cubit's own stream subscriptions
    await _statusSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _mediaItemSub?.cancel();
    await _queueProgressSub?.cancel();

    for (final sub in _downloadSubs.values) {
      sub.cancel();
    }
    _downloadSubs.clear();

    // 3. IMPORTANT: DO NOT dispose the singleton AudioHandler or AudioPlayer.
    // The background audio service lifecycle is independent of this UI Cubit.
    return super.close();
  }
}
