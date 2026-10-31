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
  })  : assert(pageNumber >= 1 && pageNumber <= 604,
            'pageNumber must be between 1 and 604'),
        assert(lineNumber >= 1 && lineNumber <= 15,
            'lineNumber must be between 1 and 15'),
        assert(words.isNotEmpty, 'Line mapping words cannot be empty'),
        words = List.unmodifiable(words);

  /// Returns the set of distinct [AyahId]s that have words on this line.
  Set<AyahId> get ayahIds => words.map((w) => w.ayahId).toSet();

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

