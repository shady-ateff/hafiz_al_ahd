import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bloc/bloc.dart';
import '../../core/audio/quran_audio_handler.dart';
import '../../core/audio/quran_audio_player.dart';
import '../../core/tracking/ayah_tracking_engine.dart';
import '../../domain/entities/audio_highlight_state.dart';
import '../../domain/entities/audio_reciter.dart';
import '../../domain/entities/ayah_timing.dart';
import '../../domain/entities/playback_position.dart';
import '../../domain/errors/quran_audio_failures.dart';
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

  StreamSubscription<QuranPlaybackStatus>? _statusSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;

  QuranAudioCubit({
    required this.getRecitersUseCase,
    required this.getSurahAudioUseCase,
    required this.audioHandler,
    required this.trackingEngine,
    required this.savePlaybackPositionUseCase,
    required this.getPlaybackPositionUseCase,
  }) : super(QuranAudioState(
          reciters: AudioReciter.kDefaultReciters,
          selectedReciter: AudioReciter.kDefaultReciter,
        )) {
    // 1. Snapshot existing background state FIRST
    _reconnectToOngoingAudio();
    // 2. Subscribe to active event streams SECOND so subsequent updates are seamlessly processed
    _initHandlerSubscriptions();
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
          final isPlaying = audioHandler.status == QuranPlaybackStatus.playing;
          final isBuffering = audioHandler.status == QuranPlaybackStatus.buffering;

          if (track != null && track.surahNumber == surahNum) {
            trackingEngine.setTimings(track.ayahTimings);
            emit(state.copyWith(
              currentSurahNumber: surahNum,
              currentSurahAudio: track,
              totalDuration: Duration(milliseconds: track.durationMs),
              playbackStatus: audioHandler.status,
              highlightState: state.highlightState.copyWith(
                clearActiveAyah: true,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              ),
            ));
          } else {
            emit(state.copyWith(
              currentSurahNumber: surahNum,
              playbackStatus: audioHandler.status,
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
    );

    emit(state.copyWith(
      currentPosition: position,
      highlightState: updatedHighlight,
    ));
  }

  void _handlePlaybackCompleted() {
    final clearedHighlight = state.highlightState.copyWith(
      clearActiveAyah: true,
      isPlaying: false,
    );

    emit(state.copyWith(
      playbackStatus: QuranPlaybackStatus.completed,
      highlightState: clearedHighlight,
    ));

    _savePosition();
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
      emit(state.copyWith(
        selectedReciter: reciter,
        highlightState: state.highlightState.copyWith(clearActiveAyah: true),
      ));

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

        emit(state.copyWith(
          isLoadingAudio: false,
          currentSurahAudio: surahAudio,
          isLocal: false,
          totalDuration: Duration(milliseconds: surahAudio.durationMs),
        ));

        // Delegate entire load, media notification, and playback start to AudioHandler
        await audioHandler.playSurah(
          surahAudio: surahAudio,
          reciterName: state.selectedReciter?.arabicName ??
              state.selectedReciter?.name ??
              'القرآن الكريم',
          localFilePath: null,
          startPosition: initialPos,
        );

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
  /// [fallbackSurahNumber] (or current surah, or Surah 1).
  Future<void> togglePlayPause({int? fallbackSurahNumber}) async {
    final isActuallyPlaying =
        state.isPlaying || audioHandler.status == QuranPlaybackStatus.playing;

    if (isActuallyPlaying) {
      await pause();
    } else if ((state.isPaused || audioHandler.status == QuranPlaybackStatus.paused) &&
        (state.currentSurahAudio != null || audioHandler.currentTrack != null)) {
      await resume();
    } else {
      // Stopped, idle, completed, or fresh start:
      // Prioritize visible page Surah first, then saved state, then Surah 1
      final surahToPlay = fallbackSurahNumber ?? state.currentSurahNumber ?? 1;
      await playSurah(surahNumber: surahToPlay);
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

  @override
  Future<void> close() async {
    // 1. Persist current listening position
    _savePosition();

    // 2. Cancel Cubit's own stream subscriptions
    await _statusSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _mediaItemSub?.cancel();

    // 3. IMPORTANT: DO NOT dispose the singleton AudioHandler or AudioPlayer.
    // The background audio service lifecycle is independent of this UI Cubit.
    return super.close();
  }
}
