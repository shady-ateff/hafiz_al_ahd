import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../../domain/entities/audio_highlight_state.dart';
import '../../domain/entities/ayah_timing.dart';
import '../../domain/entities/surah_audio.dart';
import 'quran_audio_player.dart';

/// Concrete [QuranAudioPlayer] implementation backed by the `just_audio` package.
///
/// Designed from the ground up for seamless compatibility with background audio
/// services, media notifications, lock screen controls, and AudioHandler architectures.
///
/// **ARCHITECTURAL GUARANTEES**:
/// - Encapsulates all `just_audio` processing states into domain [QuranPlaybackStatus].
/// - Enforces single Ayah and range repeat boundaries with seek-debounce guards.
/// - Exposes reactive position, duration, and status broadcast streams.
/// - Supports both online HTTP streaming and local filesystem audio paths.
class QuranAudioPlayerImpl implements QuranAudioPlayer {
  final ja.AudioPlayer _player;

  // Stream Controllers
  final StreamController<QuranPlaybackStatus> _statusController =
      StreamController<QuranPlaybackStatus>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  // Internal State
  QuranPlaybackStatus _status = QuranPlaybackStatus.idle;
  Duration _currentPosition = Duration.zero;
  Duration? _duration;
  SurahAudio? _currentTrack;
  String? _currentSource;
  bool _isLocalSource = false;

  // Repeat Configuration
  AudioRepeatMode _repeatMode = AudioRepeatMode.continuous;
  int? _rangeStartAyah;
  int? _rangeEndAyah;
  int? _repeatCount;
  int _currentRepeatIteration = 0;
  bool _rangeCompleted = false;
  AyahTiming? _activeAyahTiming;

  // Debounce flag to prevent concurrent rapid seeks
  bool _isSeeking = false;

  // Subscriptions
  StreamSubscription<ja.PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  QuranAudioPlayerImpl({ja.AudioPlayer? audioPlayer})
      : _player = audioPlayer ?? ja.AudioPlayer() {
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      final newStatus = _mapJustAudioState(state);
      if (_status != newStatus) {
        _status = newStatus;
        _statusController.add(_status);
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      _currentPosition = pos;
      _positionController.add(pos);
      _checkRepeatBoundaries(pos);

      // Self-healing synchronization: if position is advancing,
      // guarantee that _status is set to playing.
      if ((_player.playing || pos > Duration.zero) &&
          _status != QuranPlaybackStatus.playing &&
          _status != QuranPlaybackStatus.paused &&
          _status != QuranPlaybackStatus.completed) {
        _status = QuranPlaybackStatus.playing;
        _statusController.add(_status);
      }
    });

    _durationSub = _player.durationStream.listen((dur) {
      _duration = dur;
      _durationController.add(dur);
    });
  }

  QuranPlaybackStatus _mapJustAudioState(ja.PlayerState state) {
    switch (state.processingState) {
      case ja.ProcessingState.idle:
        return QuranPlaybackStatus.idle;
      case ja.ProcessingState.loading:
        return QuranPlaybackStatus.loading;
      case ja.ProcessingState.buffering:
        return state.playing
            ? QuranPlaybackStatus.playing
            : QuranPlaybackStatus.buffering;
      case ja.ProcessingState.ready:
        return state.playing
            ? QuranPlaybackStatus.playing
            : QuranPlaybackStatus.paused;
      case ja.ProcessingState.completed:
        return QuranPlaybackStatus.completed;
    }
  }

  @override
  Stream<QuranPlaybackStatus> get playbackStatusStream => _statusController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  QuranPlaybackStatus get status => _status;

  @override
  bool get isPlaying => _player.playing;

  @override
  Duration get currentPosition => _currentPosition;

  @override
  Duration? get duration => _duration;

  @override
  SurahAudio? get currentTrack => _currentTrack;

  @override
  AudioRepeatMode get repeatMode => _repeatMode;

  int? get rangeStartAyah => _rangeStartAyah;
  int? get rangeEndAyah => _rangeEndAyah;
  bool get isLocalSource => _isLocalSource;

  @override
  Future<void> loadSurah({
    required SurahAudio surahAudio,
    String? localFilePath,
    Duration? startPosition,
  }) async {
    try {
      _status = QuranPlaybackStatus.loading;
      _statusController.add(_status);

      // Reset repeat boundaries on track load
      _activeAyahTiming = null;
      _currentRepeatIteration = 0;
      _rangeCompleted = false;
      _currentTrack = surahAudio;
      _currentSource = localFilePath ?? surahAudio.audioUrl;
      _isLocalSource = localFilePath != null;
      _duration = Duration(milliseconds: surahAudio.durationMs);
      _durationController.add(_duration);

      if (localFilePath != null) {
        await _player.setFilePath(
          localFilePath,
          initialPosition: startPosition ?? Duration.zero,
        );
      } else {
        await _player.setUrl(
          surahAudio.audioUrl,
          initialPosition: startPosition ?? Duration.zero,
        );
      }

      if (startPosition != null && startPosition > Duration.zero) {
        _currentPosition = startPosition;
        _positionController.add(startPosition);
      } else {
        _currentPosition = Duration.zero;
        _positionController.add(Duration.zero);
      }

      _status = _mapJustAudioState(_player.playerState);
      _statusController.add(_status);
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] Error loading surah: $e');
      _status = QuranPlaybackStatus.error;
      _statusController.add(_status);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_currentSource == null && _currentTrack == null) return;
    try {
      _status = QuranPlaybackStatus.playing;
      _statusController.add(_status);

      // just_audio's play() Future only completes when playback finishes,
      // pauses, or stops. We initiate playback asynchronously without blocking
      // the caller (AudioHandler, Cubit, background notification receiver).
      unawaited(_player.play().catchError((e) {
        debugPrint('[QuranAudioPlayerImpl] Play error: $e');
        _status = QuranPlaybackStatus.error;
        _statusController.add(_status);
      }));
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] Play error: $e');
      _status = QuranPlaybackStatus.error;
      _statusController.add(_status);
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    try {
      _status = QuranPlaybackStatus.paused;
      _statusController.add(_status);
      await _player.pause();
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] Pause error: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      _currentPosition = Duration.zero;
      _positionController.add(Duration.zero);
      _status = QuranPlaybackStatus.idle;
      _statusController.add(_status);
      _currentTrack = null;
      _currentSource = null;
      _activeAyahTiming = null;
      _currentRepeatIteration = 0;
      _rangeCompleted = false;
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] Stop error: $e');
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_isSeeking) return;
    _isSeeking = true;
    try {
      await _player.seek(position);
      _currentPosition = position;
      _positionController.add(position);

      // If user seeks back before range end, allow range repeat to be active again
      if (_repeatMode == AudioRepeatMode.range && _currentTrack != null && _rangeEndAyah != null) {
        final maxAyah = (_rangeStartAyah != null && _rangeStartAyah! > _rangeEndAyah!)
            ? _rangeStartAyah!
            : _rangeEndAyah!;
        final endTiming = _currentTrack!.ayahTimings.cast<AyahTiming?>().firstWhere(
              (t) => t?.ayahNumber == maxAyah,
              orElse: () => null,
            );
        if (endTiming != null && position.inMilliseconds < endTiming.timestampTo) {
          _rangeCompleted = false;
        }
      }
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] Seek error: $e');
    } finally {
      _isSeeking = false;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('[QuranAudioPlayerImpl] SetVolume error: $e');
    }
  }

  @override
  Future<void> setRepeatMode(
    AudioRepeatMode mode, {
    int? rangeStartAyah,
    int? rangeEndAyah,
    int? repeatCount,
  }) async {
    _repeatMode = mode;
    _rangeStartAyah = mode == AudioRepeatMode.range ? rangeStartAyah : null;
    _rangeEndAyah = mode == AudioRepeatMode.range ? rangeEndAyah : null;
    _repeatCount = repeatCount;
    _currentRepeatIteration = 0;
    _rangeCompleted = false;
  }

  /// Sets the active Ayah timing for enforcing single Ayah repeat loops.
  ///
  /// CRITICAL ARCHITECTURAL CONTRACT:
  /// - In [AudioRepeatMode.singleAyah]: [_currentRepeatIteration] resets whenever the Ayah changes.
  /// - In [AudioRepeatMode.range]: Inter-ayah transitions WITHIN the range [start..end]
  ///   must NEVER reset [_currentRepeatIteration], preserving the loop count across the full range.
  ///   If playback leaves the range entirely, the iteration count and completed flag reset.
  void setActiveAyahTiming(AyahTiming? timing) {
    if (_repeatMode == AudioRepeatMode.singleAyah) {
      if (_activeAyahTiming?.ayahNumber != timing?.ayahNumber) {
        _currentRepeatIteration = 0;
      }
    } else if (_repeatMode == AudioRepeatMode.range) {
      if (timing != null && _rangeStartAyah != null && _rangeEndAyah != null) {
        final ayah = timing.ayahNumber;
        final minAyah = _rangeStartAyah! < _rangeEndAyah! ? _rangeStartAyah! : _rangeEndAyah!;
        // If playback returns before the start of the range, allow range repeat to re-arm
        if (ayah < minAyah) {
          _currentRepeatIteration = 0;
          _rangeCompleted = false;
        }
      }
    }
    _activeAyahTiming = timing;
  }

  void _checkRepeatBoundaries(Duration position) {
    if (_isSeeking) return;
    final posMs = position.inMilliseconds;

    // 1. Single Ayah repeat check (inclusive of boundary and slight overshoot)
    if (_repeatMode == AudioRepeatMode.singleAyah && _activeAyahTiming != null) {
      if (posMs >= _activeAyahTiming!.timestampTo) {
        if (_repeatCount == null || _repeatCount! <= 0 || _currentRepeatIteration < _repeatCount!) {
          _currentRepeatIteration++;
          seekTo(Duration(milliseconds: _activeAyahTiming!.timestampFrom));
          return;
        }
      }
    }

    // 2. Range repeat check
    if (_repeatMode == AudioRepeatMode.range &&
        _rangeStartAyah != null &&
        _rangeEndAyah != null &&
        _currentTrack != null) {
      final minAyah = _rangeStartAyah! < _rangeEndAyah! ? _rangeStartAyah! : _rangeEndAyah!;
      final maxAyah = _rangeStartAyah! > _rangeEndAyah! ? _rangeStartAyah! : _rangeEndAyah!;

      final startTiming = _currentTrack!.ayahTimings.cast<AyahTiming?>().firstWhere(
            (t) => t?.ayahNumber == minAyah,
            orElse: () => null,
          );
      final endTiming = _currentTrack!.ayahTimings.cast<AyahTiming?>().firstWhere(
            (t) => t?.ayahNumber == maxAyah,
            orElse: () => null,
          );

      if (startTiming != null && endTiming != null) {
        if (posMs >= endTiming.timestampTo) {
          // If all requested range repetitions already finished, allow playback to advance
          if (_rangeCompleted) return;

          if (_repeatCount == null || _repeatCount! <= 0 || _currentRepeatIteration < _repeatCount!) {
            _currentRepeatIteration++;
            seekTo(Duration(milliseconds: startTiming.timestampFrom));
            return;
          } else {
            // Repetitions finished! Playback continues past endTiming into subsequent Ayahs
            _rangeCompleted = true;
            _currentRepeatIteration = 0;
          }
        } else if (posMs < startTiming.timestampFrom) {
          // If position moves before the start timing, reset completed flag
          _rangeCompleted = false;
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();

    await _statusController.close();
    await _positionController.close();
    await _durationController.close();

    await _player.dispose();
  }
}
