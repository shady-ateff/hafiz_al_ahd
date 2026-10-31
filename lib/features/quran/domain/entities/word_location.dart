import 'package:equatable/equatable.dart';
import 'ayah_id.dart';

/// Identifies the precise sequential position of an individual word within an Ayah.
class WordLocation extends Equatable {
  final int surahNumber;
  final int ayahNumber;
  final int wordIndex;

  const WordLocation({
    required this.surahNumber,
    required this.ayahNumber,
    required this.wordIndex,
  })  : assert(surahNumber >= 1 && surahNumber <= 114,
            'surahNumber must be between 1 and 114'),
        assert(ayahNumber >= 1, 'ayahNumber must be at least 1'),
        assert(wordIndex >= 1, 'wordIndex must be at least 1');

  /// Creates a [WordLocation] from an existing [AyahId] and word index.
  factory WordLocation.fromAyahId({
    required AyahId ayahId,
    required int wordIndex,
  }) {
    return WordLocation(
      surahNumber: ayahId.surahNumber,
      ayahNumber: ayahId.ayahNumber,
      wordIndex: wordIndex,
    );
  }

  /// Creates a [WordLocation] from a 3-part colon-separated string (e.g., "1:1:1", "2:255:10").
  factory WordLocation.fromString(String value) {
    final parts = value.split(':');
    if (parts.length != 3) {
      throw ArgumentError.value(
        value,
        'value',
        'WordLocation string must be formatted as surah:ayah:word (e.g. 1:1:1)',
      );
    }
    final surah = int.tryParse(parts[0].trim());
    final ayah = int.tryParse(parts[1].trim());
    final word = int.tryParse(parts[2].trim());
    if (surah == null || ayah == null || word == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Surah, Ayah, and wordIndex components must be valid integers',
      );
    }
    return WordLocation(
      surahNumber: surah,
      ayahNumber: ayah,
      wordIndex: word,
    );
  }

  /// The parent [AyahId] of this word.
  AyahId get ayahId =>
      AyahId(surahNumber: surahNumber, ayahNumber: ayahNumber);

  /// Returns the canonical colon-separated string representation (e.g., "2:255:1").
  String get formatted => '$surahNumber:$ayahNumber:$wordIndex';

  @override
  String toString() => formatted;

  @override
  List<Object?> get props => [surahNumber, ayahNumber, wordIndex];
}

