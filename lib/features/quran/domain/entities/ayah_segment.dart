import 'package:equatable/equatable.dart';
import 'ayah_id.dart';

/// Represents the contiguous slice of an Ayah located within a single physical line of a page.
///
/// **Important Note on Word Indices:**
/// [wordStart] and [wordEnd] represent the **0-based slice indices within the physical line's**
/// `words` list (i.e. `line.words.sublist(wordStart, wordEnd + 1)` yields this segment's words).
/// They are NOT the 1-based word indices within the Ayah (which are tracked in [WordLocation.wordIndex]).
class AyahSegment extends Equatable {
  final AyahId ayahId;
  final int pageNumber;
  final int lineNumber;
  final int wordStart;
  final int wordEnd;
  final String qcfText;

  AyahSegment({
    required this.ayahId,
    required this.pageNumber,
    required this.lineNumber,
    required this.wordStart,
    required this.wordEnd,
    required this.qcfText,
  }) {
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
    if (wordStart < 0) {
      throw ArgumentError.value(
        wordStart,
        'wordStart',
        'wordStart must be non-negative (received: $wordStart)',
      );
    }
    if (wordEnd < wordStart) {
      throw ArgumentError.value(
        wordEnd,
        'wordEnd',
        'wordEnd must be greater than or equal to wordStart (received: wordStart=$wordStart, wordEnd=$wordEnd)',
      );
    }
    if (qcfText.trim().isEmpty) {
      throw ArgumentError.value(
        qcfText,
        'qcfText',
        'qcfText cannot be empty',
      );
    }
  }

  /// Convenience getter for the Surah number.
  int get surahNumber => ayahId.surahNumber;

  /// Convenience getter for the Ayah number.
  int get ayahNumber => ayahId.ayahNumber;

  /// Total number of words encompassed by this segment on this line (inclusive: wordEnd - wordStart + 1).
  int get wordCount => wordEnd - wordStart + 1;

  @override
  String toString() =>
      'AyahSegment($ayahId, p.$pageNumber l.$lineNumber words: $wordStart..$wordEnd)';

  @override
  List<Object?> get props =>
      [ayahId, pageNumber, lineNumber, wordStart, wordEnd, qcfText];
}
