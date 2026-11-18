import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';

/// Repeat playback modes supported by the Quran Audio engine.
enum AudioRepeatMode {
  /// Continuous playback without repetition.
  off,

  /// Repeat the currently reciting Ayah continuously.
  singleAyah,

  /// Repeat a defined range of Ayahs continuously.
  range,
}

/// Represents the dedicated UI highlighting state driven purely by audio playback tracking.
///
/// **ARCHITECTURAL INVARIANT**:
/// This state is strictly decoupled from the manual selection state (`QuranCubit.selectedAyahId`).
/// Audio playback will never mutate or overwrite user manual selections or Tafsir interaction.
class AudioHighlightState extends Equatable {
  /// The Ayah currently being recited according to the audio playback position.
  final AyahId? activeAyah;

  /// Whether audio is actively playing.
  final bool isPlaying;

  /// Whether audio is currently buffering / loading.
  final bool isBuffering;

  /// Current repeat mode.
  final AudioRepeatMode repeatMode;

  /// Start of the Ayah repetition range (when [repeatMode] is [AudioRepeatMode.range]).
  final AyahId? repeatRangeStart;

  /// End of the Ayah repetition range (when [repeatMode] is [AudioRepeatMode.range]).
  final AyahId? repeatRangeEnd;

  const AudioHighlightState({
    this.activeAyah,
    this.isPlaying = false,
    this.isBuffering = false,
    this.repeatMode = AudioRepeatMode.off,
    this.repeatRangeStart,
    this.repeatRangeEnd,
  });

  /// Initial idle state.
  static const AudioHighlightState idle = AudioHighlightState();

  AudioHighlightState copyWith({
    AyahId? activeAyah,
    bool clearActiveAyah = false,
    bool? isPlaying,
    bool? isBuffering,
    AudioRepeatMode? repeatMode,
    AyahId? repeatRangeStart,
    bool clearRangeStart = false,
    AyahId? repeatRangeEnd,
    bool clearRangeEnd = false,
  }) {
    return AudioHighlightState(
      activeAyah: clearActiveAyah ? null : (activeAyah ?? this.activeAyah),
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      repeatMode: repeatMode ?? this.repeatMode,
      repeatRangeStart: clearRangeStart ? null : (repeatRangeStart ?? this.repeatRangeStart),
      repeatRangeEnd: clearRangeEnd ? null : (repeatRangeEnd ?? this.repeatRangeEnd),
    );
  }

  @override
  List<Object?> get props => [
        activeAyah,
        isPlaying,
        isBuffering,
        repeatMode,
        repeatRangeStart,
        repeatRangeEnd,
      ];
}
