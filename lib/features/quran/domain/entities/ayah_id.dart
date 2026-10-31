import 'package:equatable/equatable.dart';

/// Uniquely identifies an Ayah within the Holy Quran by its Surah and Ayah numbers.
class AyahId extends Equatable {
  final int surahNumber;
  final int ayahNumber;

  const AyahId({
    required this.surahNumber,
    required this.ayahNumber,
  })  : assert(surahNumber >= 1 && surahNumber <= 114,
            'surahNumber must be between 1 and 114'),
        assert(ayahNumber >= 1, 'ayahNumber must be at least 1');

  /// Creates an [AyahId] from a standard colon-separated string (e.g., "1:1", "2:255").
  factory AyahId.fromString(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      throw ArgumentError.value(
        value,
        'value',
        'AyahId string must be formatted as surah:ayah (e.g. 2:255)',
      );
    }
    final surah = int.tryParse(parts[0].trim());
    final ayah = int.tryParse(parts[1].trim());
    if (surah == null || ayah == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Surah and Ayah components must be valid integers',
      );
    }
    return AyahId(surahNumber: surah, ayahNumber: ayah);
  }

  /// Returns the canonical colon-separated string representation (e.g., "2:255").
  String get formatted => '$surahNumber:$ayahNumber';

  @override
  String toString() => formatted;

  @override
  List<Object?> get props => [surahNumber, ayahNumber];
}

