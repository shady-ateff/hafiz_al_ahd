import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import '../../../quran/data/datasources/surah_names.dart';
import '../../domain/entities/audio_highlight_state.dart';
import '../../domain/entities/ayah_timing.dart';
import '../../domain/entities/playback_position.dart';
import '../../domain/entities/surah_audio.dart';
import '../../domain/usecases/get_surah_audio_use_case.dart';
import '../../domain/usecases/save_playback_position_use_case.dart';
import 'quran_audio_player.dart';
import 'quran_audio_player_impl.dart';

/// AudioHandler for the Quran Audio subsystem.
///
/// **ARCHITECTURAL ROLE**:
/// - Acts as the SOLE orchestrator for audio playback, media notifications, lockscreen controls,
///   background position persistence, and audio focus management.
/// - Autonomous track navigation: Next / Previous Surah transitions are executed internally
///   via [GetSurahAudioUseCase] with generation token concurrency guards.
/// - Background Persistence: Persists playback position periodically (every 10s) and on
///   pause, stop, completed, track switch, and task dismiss, completely independent of the UI Cubit.
class QuranAudioHandler extends BaseAudioHandler with SeekHandler {
  final QuranAudioPlayer player;
  final GetSurahAudioUseCase? getSurahAudioUseCase;
  final SavePlaybackPositionUseCase? savePlaybackPositionUseCase;
  final AudioSession? audioSession;

  StreamSubscription<QuranPlaybackStatus>? _statusSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  SurahAudio? _currentSurahAudio;
  bool _wasPlayingBeforeInterruption = false;
  int _interruptionDepth = 0;
  bool _isDucked = false;

  // Unified Generation Token & Navigation Safety across ALL track change sources
  bool _isNavigating = false;
  int _trackGenerationToken = 0;

  // Background Position Persistence State & Queue
  int _lastSavedPositionMs = 0;
  int _activeAyahNumber = 1;
  int _persistenceGeneration = 0;
  int _lastPersistedGeneration = 0;
  Future<void> _persistenceChain = Future.value();

  QuranAudioHandler({
    required this.player,
    this.getSurahAudioUseCase,
    this.savePlaybackPositionUseCase,
    this.audioSession,
  }) {
    _initPlayerListeners();
    _initAudioSession();
    _broadcastPlaybackState();
  }

  // --- Exposed Audio State Getters ---

  QuranPlaybackStatus get status => player.status;
  bool get isActuallyPlaying =>
      player.status == QuranPlaybackStatus.playing || player.isPlaying;
  Duration get currentPosition => player.currentPosition;
  Duration? get duration => player.duration;
  SurahAudio? get currentTrack => _currentSurahAudio ?? player.currentTrack;
  AudioRepeatMode get repeatMode => player.repeatMode;
  int get activeAyahNumber => _activeAyahNumber;
  bool get isInterrupted => _interruptionDepth > 0;
  bool get isDucked => _isDucked;
  bool get isNavigating => _isNavigating;

  Stream<QuranPlaybackStatus> get playbackStatusStream => player.playbackStatusStream;
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;

  void _initPlayerListeners() {
    _statusSub = player.playbackStatusStream.listen((status) {
      _broadcastPlaybackState();
      if (status == QuranPlaybackStatus.completed) {
        _persistPosition();
      }
    });

    _posSub = player.positionStream.listen((pos) {
      _broadcastPlaybackState();
      _resolveActiveAyah(pos);

      // Periodic background persistence every 10 seconds during active playback
      final posMs = pos.inMilliseconds;
      if (player.status == QuranPlaybackStatus.playing &&
          (posMs - _lastSavedPositionMs).abs() >= 10000) {
        _persistPosition();
      }
    });

    _durSub = player.durationStream.listen((dur) {
      if (dur != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: dur));
      }
      _broadcastPlaybackState();
    });
  }

  void _resolveActiveAyah(Duration pos) {
    final track = _currentSurahAudio;
    if (track == null || track.ayahTimings.isEmpty) return;

    final ms = pos.inMilliseconds;
    for (final timing in track.ayahTimings) {
      if (ms >= timing.timestampFrom && ms < timing.timestampTo) {
        _activeAyahNumber = timing.ayahNumber;
        break;
      }
    }
  }

  /// Persists the current playback position asynchronously with strict FIFO ordering,
  /// monotonic generation guards, and synchronous snapshot capture to eliminate race conditions.
  Future<void> _persistPosition() {
    final track = _currentSurahAudio;
    if (track == null || savePlaybackPositionUseCase == null) {
      return Future.value();
    }

    // 1. Capture atomic immutable snapshot synchronously BEFORE any await
    final snapshot = _PositionPersistenceSnapshot(
      surahNumber: track.surahNumber,
      reciterId: track.reciterId,
      positionMs: player.currentPosition.inMilliseconds,
      ayahNumber: _activeAyahNumber,
      durationMs: track.durationMs,
      generation: ++_persistenceGeneration,
    );

    _lastSavedPositionMs = snapshot.positionMs;

    // 2. Queue write sequentially via Future chain to guarantee FIFO ordering
    _persistenceChain = _persistenceChain.then((_) async {
      // Monotonic guard: If a newer persistence generation was already queued or succeeded, discard older
      if (snapshot.generation < _lastPersistedGeneration ||
          snapshot.generation < _persistenceGeneration) {
        return;
      }
      try {
        await savePlaybackPositionUseCase!(PlaybackPosition(
          reciterId: snapshot.reciterId,
          surahNumber: snapshot.surahNumber,
          positionMs: snapshot.positionMs,
          currentAyahNumber: snapshot.ayahNumber,
          durationMs: snapshot.durationMs,
        ));
        if (snapshot.generation > _lastPersistedGeneration) {
          _lastPersistedGeneration = snapshot.generation;
        }
      } catch (e) {
        debugPrint('[QuranAudioHandler] Position persistence error: $e');
      }
    });

    return _persistenceChain;
  }

  Future<void> _initAudioSession() async {
    try {
      final session = audioSession ?? await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      _interruptionSub = session.interruptionEventStream.listen(_handleInterruption);

      _noisySub = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged: pause immediately and cancel auto-resume
        _wasPlayingBeforeInterruption = false;
        pause();
      });
    } catch (e) {
      debugPrint('[QuranAudioHandler] AudioSession setup bypassed or failed: $e');
    }
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      _interruptionDepth++;

      if (_interruptionDepth == 1) {
        // Capture whether we were actively reciting before the first interruption began
        _wasPlayingBeforeInterruption = player.status == QuranPlaybackStatus.playing;
      }

      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_wasPlayingBeforeInterruption) {
            _isDucked = true;
            player.setVolume(0.2);
          }
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_wasPlayingBeforeInterruption) {
            player.pause();
            _broadcastPlaybackState();
          }
          break;
      }
    } else {
      _interruptionDepth = (_interruptionDepth - 1).clamp(0, 100);

      // Duck ended: restore volume to full if ducked
      if (event.type == AudioInterruptionType.duck) {
        if (_isDucked) {
          _isDucked = false;
          player.setVolume(1.0);
        }
      }

      // Safe resume: ONLY resume if all nested interruptions ended,
      // the event type was pause/unknown, and user did NOT manually pause during the call
      if (_interruptionDepth == 0 &&
          (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.unknown) &&
          _wasPlayingBeforeInterruption) {
        player.play();
        _wasPlayingBeforeInterruption = false;
        _broadcastPlaybackState();
      }
    }
  }

  /// Loads and starts playing a Surah.
  ///
  /// Increments the unified [_trackGenerationToken] to immediately invalidate and discard
  /// any background in-flight track navigations (e.g. from [skipToNext] / [skipToPrevious]).
  Future<void> playSurah({
    required SurahAudio surahAudio,
    String? reciterName,
    String? localFilePath,
    Duration? startPosition,
  }) async {
    // Invalidate any in-flight navigation fetches immediately
    ++_trackGenerationToken;
    _isNavigating = false;

    // Persist position of existing track before switching
    if (_currentSurahAudio != null) {
      await _persistPosition();
    }

    _currentSurahAudio = surahAudio;
    _lastSavedPositionMs = startPosition?.inMilliseconds ?? 0;
    _activeAyahNumber = 1;

    final name = reciterName ?? mediaItem.value?.artist ?? 'القرآن الكريم';

    updateMediaItemForSurah(
      surahNumber: surahAudio.surahNumber,
      reciterName: name,
      duration: Duration(milliseconds: surahAudio.durationMs),
    );

    await player.loadSurah(
      surahAudio: surahAudio,
      localFilePath: localFilePath,
      startPosition: startPosition,
    );
    await player.play();
    _broadcastPlaybackState();
  }

  /// Sets repeat mode configuration.
  Future<void> setQuranRepeatMode(
    AudioRepeatMode mode, {
    int? rangeStartAyah,
    int? rangeEndAyah,
    int? repeatCount,
  }) async {
    await player.setRepeatMode(
      mode,
      rangeStartAyah: rangeStartAyah,
      rangeEndAyah: rangeEndAyah,
      repeatCount: repeatCount,
    );
  }

  /// Sets active ayah timing for enforcing single ayah loops.
  void setActiveAyahTiming(AyahTiming? timing) {
    if (timing != null) {
      _activeAyahNumber = timing.ayahNumber;
    }
    if (player is QuranAudioPlayerImpl) {
      (player as QuranAudioPlayerImpl).setActiveAyahTiming(timing);
    }
  }

  /// Updates the active [MediaItem] displayed in the Android system media notification
  /// and lock screen controls.
  void updateMediaItemForSurah({
    required int surahNumber,
    required String reciterName,
    Duration? duration,
    Uri? artUri,
  }) {
    final surahTitle = 'سورة ${getSurahName(surahNumber)}';

    final item = MediaItem(
      id: 'surah_$surahNumber',
      album: 'القرآن الكريم',
      title: surahTitle,
      artist: reciterName,
      duration: duration ?? player.duration,
      artUri: artUri,
      extras: {
        'surahNumber': surahNumber,
      },
    );

    mediaItem.add(item);
    _broadcastPlaybackState();
  }

  void _broadcastPlaybackState() {
    final isPlaying = isActuallyPlaying;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _mapToAudioProcessingState(player.status),
        playing: isPlaying,
        updatePosition: player.currentPosition,
        bufferedPosition: player.currentPosition,
        speed: 1.0,
      ),
    );
  }

  AudioProcessingState _mapToAudioProcessingState(QuranPlaybackStatus status) {
    switch (status) {
      case QuranPlaybackStatus.idle:
        return AudioProcessingState.idle;
      case QuranPlaybackStatus.loading:
        return AudioProcessingState.loading;
      case QuranPlaybackStatus.buffering:
        return AudioProcessingState.buffering;
      case QuranPlaybackStatus.playing:
      case QuranPlaybackStatus.paused:
        return AudioProcessingState.ready;
      case QuranPlaybackStatus.completed:
        return AudioProcessingState.completed;
      case QuranPlaybackStatus.error:
        return AudioProcessingState.error;
    }
  }

  @override
  Future<void> play() async {
    _wasPlayingBeforeInterruption = false;
    await player.play();
    _broadcastPlaybackState();
  }

  @override
  Future<void> pause() async {
    _wasPlayingBeforeInterruption = false;
    await _persistPosition();
    await player.pause();
    _broadcastPlaybackState();
  }

  @override
  Future<void> stop() async {
    _wasPlayingBeforeInterruption = false;
    _interruptionDepth = 0;
    _isDucked = false;
    await _persistPosition();
    await player.stop();
    _broadcastPlaybackState();
  }

  @override
  Future<void> seek(Duration position) async {
    await player.seekTo(position);
    _broadcastPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    if (_currentSurahAudio == null || getSurahAudioUseCase == null) return;

    // Policy: Debounce rapid successive taps while navigation is in progress
    if (_isNavigating) {
      debugPrint('[QuranAudioHandler] skipToNext: Ignored rapid tap while navigating');
      return;
    }

    final currentSurah = _currentSurahAudio!.surahNumber;
    if (currentSurah >= 114) {
      // Boundary reached: Last Surah (An-Nas) -> Safe no-op
      debugPrint('[QuranAudioHandler] skipToNext: Already at last Surah (114)');
      return;
    }

    _isNavigating = true;
    final token = ++_trackGenerationToken;

    try {
      await _persistPosition();

      final nextSurah = currentSurah + 1;
      final currentReciterId = _currentSurahAudio!.reciterId;
      final result = await getSurahAudioUseCase!(
        surahNumber: nextSurah,
        reciterId: currentReciterId,
      );

      // Invalidation check: Check if token changed due to another navigation OR direct playSurah
      if (token != _trackGenerationToken) {
        debugPrint('[QuranAudioHandler] skipToNext: Discarding in-flight response (token mismatch)');
        return;
      }

      await result.fold(
        (failure) async {
          debugPrint('[QuranAudioHandler] skipToNext failed: ${failure.message}');
          // Safe error handling: Existing track and media notification remain stable
        },
        (surahAudio) async {
          if (token != _trackGenerationToken) return;
          await playSurah(
            surahAudio: surahAudio,
            reciterName: mediaItem.value?.artist,
          );
        },
      );
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentSurahAudio == null || getSurahAudioUseCase == null) return;

    // Policy: Debounce rapid successive taps while navigation is in progress
    if (_isNavigating) {
      debugPrint('[QuranAudioHandler] skipToPrevious: Ignored rapid tap while navigating');
      return;
    }

    final currentSurah = _currentSurahAudio!.surahNumber;
    if (currentSurah <= 1) {
      // Boundary reached: First Surah (Al-Fatihah) -> Seek to beginning
      await seek(Duration.zero);
      return;
    }

    _isNavigating = true;
    final token = ++_trackGenerationToken;

    try {
      await _persistPosition();

      final prevSurah = currentSurah - 1;
      final currentReciterId = _currentSurahAudio!.reciterId;
      final result = await getSurahAudioUseCase!(
        surahNumber: prevSurah,
        reciterId: currentReciterId,
      );

      if (token != _trackGenerationToken) {
        debugPrint('[QuranAudioHandler] skipToPrevious: Discarding in-flight response (token mismatch)');
        return;
      }

      await result.fold(
        (failure) async {
          debugPrint('[QuranAudioHandler] skipToPrevious failed: ${failure.message}');
        },
        (surahAudio) async {
          if (token != _trackGenerationToken) return;
          await playSurah(
            surahAudio: surahAudio,
            reciterName: mediaItem.value?.artist,
          );
        },
      );
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Persist position and stop playback when app task is swiped away
    await _persistPosition();
    await stop();
    await super.onTaskRemoved();
  }

  Future<void> disposeHandler() async {
    await _statusSub?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
  }
}

/// Private immutable snapshot captured synchronously to eliminate async race conditions
/// and guarantee FIFO, monotonically increasing persistence ordering.
class _PositionPersistenceSnapshot {
  final int surahNumber;
  final String reciterId;
  final int positionMs;
  final int ayahNumber;
  final int durationMs;
  final int generation;

  const _PositionPersistenceSnapshot({
    required this.surahNumber,
    required this.reciterId,
    required this.positionMs,
    required this.ayahNumber,
    required this.durationMs,
    required this.generation,
  });
}
