import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';

/// The high-level playback state of the Quran Audio engine.
enum QuranPlaybackStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  error,
}

/// Abstract player contract decoupling presentation/business logic from underlying
/// audio engine packages (e.g. just_audio, audioplayers, audio_service).
abstract class QuranAudioPlayer {
  /// Stream emitting playback status changes.
  Stream<QuranPlaybackStatus> get playbackStatusStream;

  /// Stream emitting continuous playback position updates.
  Stream<Duration> get positionStream;

  /// Stream emitting the total resolved audio duration.
  Stream<Duration?> get durationStream;

  /// Current playback status.
  QuranPlaybackStatus get status;

  /// Whether playback is actively running or scheduled to play.
  bool get isPlaying;

  /// Current position.
  Duration get currentPosition;

  /// Total duration if loaded.
  Duration? get duration;

  /// Currently active Surah audio track.
  SurahAudio? get currentTrack;

  /// Currently configured repeat mode.
  AudioRepeatMode get repeatMode;

  /// Loads and prepares a Surah for playback.
  ///
  /// If [localFilePath] is provided and valid, playback is sourced from local storage.
  /// Otherwise, [surahAudio.audioUrl] is streamed over the network.
  Future<void> loadSurah({
    required SurahAudio surahAudio,
    String? localFilePath,
    Duration? startPosition,
  });

  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses active playback.
  Future<void> pause();

  /// Stops playback and resets position to start.
  Future<void> stop();

  /// Seeks to a specific timestamp within the active track.
  Future<void> seekTo(Duration position);

  /// Sets the audio volume (0.0 to 1.0) for audio focus management and ducking.
  Future<void> setVolume(double volume);

  /// Configures repeat behavior.
  ///
  /// If [repeatCount] is provided and > 0, repeats for exactly [repeatCount]
  /// cycles before advancing. If null or <= 0, repeats indefinitely.
  Future<void> setRepeatMode(
    AudioRepeatMode mode, {
    int? rangeStartAyah,
    int? rangeEndAyah,
    int? repeatCount,
  });

  /// Releases resources and disposes player listeners.
  Future<void> dispose();
}
