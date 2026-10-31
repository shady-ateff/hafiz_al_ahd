import 'package:equatable/equatable.dart';
import 'ayah_id.dart';

/// Represents the contiguous slice of an Ayah that appears on a single physical line of a page.
class AyahSegment extends Equatable {
  final AyahId ayahId;
  final int pageNumber;
  final int lineNumber;
  final int wordStart;
  final int wordEnd;
  final String qcfText;

  const AyahSegment({
    required this.ayahId,
    required this.pageNumber,
    required this.lineNumber,
    required this.wordStart,
    required this.wordEnd,
    required this.qcfText,
  })  : assert(pageNumber >= 1 && pageNumber <= 604,
            'pageNumber must be between 1 and 604'),
        assert(lineNumber >= 1 && lineNumber <= 15,
            'lineNumber must be between 1 and 15'),
        assert(wordStart >= 0, 'wordStart must be non-negative'),
        assert(wordEnd >= wordStart,
            'wordEnd must be greater than or equal to wordStart'),
        assert(qcfText.length > 0, 'qcfText cannot be empty');

  /// Convenience getter for the Surah number.
  int get surahNumber => ayahId.surahNumber;

  /// Convenience getter for the Ayah number.
  int get ayahNumber => ayahId.ayahNumber;

  /// Total number of words encompassed by this segment (inclusive: wordEnd - wordStart + 1).
  int get wordCount => wordEnd - wordStart + 1;

  @override
  String toString() =>
      'AyahSegment($ayahId, p.$pageNumber l.$lineNumber words: $wordStart..$wordEnd)';

  @override
  List<Object?> get props =>
      [ayahId, pageNumber, lineNumber, wordStart, wordEnd, qcfText];
}

