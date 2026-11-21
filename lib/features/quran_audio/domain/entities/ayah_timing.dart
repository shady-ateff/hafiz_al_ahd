import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';

/// Represents the playback timing boundaries for a single Ayah within a Surah audio file.
///
/// All timing values are strictly in integer milliseconds.
class AyahTiming extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Ayah number within the Surah (>= 1).
  final int ayahNumber;

  /// Start timestamp in milliseconds from the beginning of the Surah audio.
  final int timestampFrom;

  /// End timestamp in milliseconds from the beginning of the Surah audio.
  final int timestampTo;

  /// Expected playback duration of this Ayah in milliseconds.
  final int duration;

  AyahTiming({
    required this.surahNumber,
    required this.ayahNumber,
    required this.timestampFrom,
    required this.timestampTo,
    int? duration,
  }) : duration = duration ?? (timestampTo >= timestampFrom ? timestampTo - timestampFrom : 0) {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114',
      );
    }
    if (ayahNumber < 1) {
      throw ArgumentError.value(
        ayahNumber,
        'ayahNumber',
        'ayahNumber must be at least 1',
      );
    }
    if (timestampFrom < 0) {
      throw ArgumentError.value(
        timestampFrom,
        'timestampFrom',
        'timestampFrom cannot be negative',
      );
    }
    if (timestampTo < timestampFrom) {
      throw ArgumentError(
        'timestampTo ($timestampTo) cannot be less than timestampFrom ($timestampFrom)',
      );
    }
  }

  /// Canonical [AyahId] identifying this Ayah in the Quran domain.
  AyahId get ayahId => AyahId(surahNumber: surahNumber, ayahNumber: ayahNumber);

  /// Formatted key (e.g. "1:1", "2:255").
  String get verseKey => '$surahNumber:$ayahNumber';

  /// Whether a given audio position (in milliseconds) falls within this timing interval.
  bool containsPosition(int positionMs) {
    return positionMs >= timestampFrom && positionMs < timestampTo;
  }

  @override
  List<Object?> get props => [
        surahNumber,
        ayahNumber,
        timestampFrom,
        timestampTo,
        duration,
      ];

  @override
  String toString() =>
      'AyahTiming($verseKey: $timestampFrom..$timestampTo ms, duration: $duration ms)';
}
