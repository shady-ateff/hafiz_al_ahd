import 'package:equatable/equatable.dart';

/// Represents the persisted playback state of the Quran Audio player.
///
/// Used to restore the user's last listening position across application restarts.
class PlaybackPosition extends Equatable {
  /// Reciter ID of the active recording.
  final String reciterId;

  /// Surah number being played (1 to 114).
  final int surahNumber;

  /// Playback position in milliseconds from the start of the audio file.
  final int positionMs;

  /// Ayah number active at this position (>= 1).
  final int currentAyahNumber;

  /// Total duration in milliseconds (if known).
  final int? durationMs;

  /// Timestamp when this position was recorded.
  final DateTime updatedAt;

  PlaybackPosition({
    required this.reciterId,
    required this.surahNumber,
    required this.positionMs,
    required this.currentAyahNumber,
    this.durationMs,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now() {
    if (reciterId.trim().isEmpty) {
      throw ArgumentError.value(reciterId, 'reciterId', 'reciterId cannot be empty');
    }
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114',
      );
    }
    if (positionMs < 0) {
      throw ArgumentError.value(positionMs, 'positionMs', 'positionMs cannot be negative');
    }
    if (currentAyahNumber < 1) {
      throw ArgumentError.value(
        currentAyahNumber,
        'currentAyahNumber',
        'currentAyahNumber must be at least 1',
      );
    }
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'durationMs cannot be negative');
    }
  }

  /// Converts position to standard [Duration].
  Duration get positionDuration => Duration(milliseconds: positionMs);

  /// Converts duration to standard [Duration]? if available.
  Duration? get totalDuration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;

  @override
  List<Object?> get props => [
        reciterId,
        surahNumber,
        positionMs,
        currentAyahNumber,
        durationMs,
        updatedAt,
      ];
}
