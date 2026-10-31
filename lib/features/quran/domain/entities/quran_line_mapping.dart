import 'package:equatable/equatable.dart';
import 'ayah_id.dart';
import 'quran_word.dart';

/// Represents the interactive word-level mapping for a physical line in the Mushaf.
class QuranLineMapping extends Equatable {
  final int pageNumber;
  final int lineNumber;
  final List<QuranWord> words;

  QuranLineMapping({
    required this.pageNumber,
    required this.lineNumber,
    required List<QuranWord> words,
  })  : words = List<QuranWord>.unmodifiable(words) {
    if (pageNumber < 1 || pageNumber > 604) {
      throw ArgumentError.value(
        pageNumber,
        'pageNumber',
        'pageNumber must be between 1 and 604 (received: $pageNumber)',
      );
    }
    if (lineNumber < 1 || lineNumber > 15) {
      throw ArgumentError.value(
        lineNumber,
        'lineNumber',
        'lineNumber must be between 1 and 15 (received: $lineNumber)',
      );
    }
    if (words.isEmpty) {
      throw ArgumentError.value(
        words,
        'words',
        'QuranLineMapping words list cannot be empty for page $pageNumber line $lineNumber',
      );
    }
  }

  /// Returns an unmodifiable set of distinct [AyahId]s that have words on this line.
  Set<AyahId> get ayahIds => Set<AyahId>.unmodifiable(words.map((w) => w.ayahId));

  /// Checks whether a given [AyahId] has any words on this line.
  bool containsAyah(AyahId ayahId) => words.any((w) => w.ayahId == ayahId);

  /// Total number of words on this physical line.
  int get wordCount => words.length;

  /// Reconstructs the full line QCF text from its word components.
  String get reconstructedQcfText => words.map((w) => w.qcfText).join(' ');

  @override
  String toString() =>
      'QuranLineMapping(p.$pageNumber, l.$lineNumber, ${words.length} words, ayahs: ${ayahIds.map((e) => e.formatted).join(", ")})';

  @override
  List<Object?> get props => [pageNumber, lineNumber, words];
}
