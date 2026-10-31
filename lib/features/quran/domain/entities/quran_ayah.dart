import 'package:equatable/equatable.dart';
import 'ayah_id.dart';
import 'ayah_segment.dart';

/// Represents a full Ayah with its text, physical boundaries, and line segments.
class QuranAyah extends Equatable {
  final AyahId id;
  final int pageNumber;
  final int endPageNumber;
  final String uthmaniText;
  final int wordsCount;
  final List<AyahSegment> segments;

  QuranAyah({
    required this.id,
    required this.pageNumber,
    required this.endPageNumber,
    required this.uthmaniText,
    required this.wordsCount,
    required List<AyahSegment> segments,
  })  : segments = List<AyahSegment>.unmodifiable(segments) {
    if (pageNumber < 1 || pageNumber > 604) {
      throw ArgumentError.value(
        pageNumber,
        'pageNumber',
        'pageNumber must be between 1 and 604 (received: $pageNumber)',
      );
    }
    if (endPageNumber < pageNumber || endPageNumber > 604) {
      throw ArgumentError.value(
        endPageNumber,
        'endPageNumber',
        'endPageNumber must be between pageNumber ($pageNumber) and 604 (received: $endPageNumber)',
      );
    }
    if (uthmaniText.trim().isEmpty) {
      throw ArgumentError.value(
        uthmaniText,
        'uthmaniText',
        'uthmaniText cannot be empty',
      );
    }
    if (wordsCount < 1) {
      throw ArgumentError.value(
        wordsCount,
        'wordsCount',
        'wordsCount must be greater than 0 (received: $wordsCount)',
      );
    }
    if (segments.isEmpty) {
      throw ArgumentError.value(
        segments,
        'segments',
        'segments cannot be empty for Ayah $id',
      );
    }

    // Consistency Rule 1: pageNumber must equal the first segment's pageNumber
    if (pageNumber != segments.first.pageNumber) {
      throw ArgumentError(
        'Inconsistent pageNumber: ayah pageNumber ($pageNumber) must equal first segment page (${segments.first.pageNumber}) for Ayah $id',
      );
    }

    // Consistency Rule 2: endPageNumber must equal the last segment's pageNumber
    if (endPageNumber != segments.last.pageNumber) {
      throw ArgumentError(
        'Inconsistent endPageNumber: ayah endPageNumber ($endPageNumber) must equal last segment page (${segments.last.pageNumber}) for Ayah $id',
      );
    }

    // Consistency Rule 3: wordsCount must match the sum of words across segments
    final totalSegmentWords =
        segments.fold<int>(0, (sum, s) => sum + s.wordCount);
    if (wordsCount != totalSegmentWords) {
      throw ArgumentError(
        'Inconsistent wordsCount: ayah wordsCount ($wordsCount) does not match sum of segment words ($totalSegmentWords) for Ayah $id',
      );
    }

    // Consistency Rule 4: Segments must be strictly ordered by page, then line
    for (int i = 1; i < segments.length; i++) {
      final prev = segments[i - 1];
      final curr = segments[i];
      if (curr.pageNumber < prev.pageNumber ||
          (curr.pageNumber == prev.pageNumber &&
              curr.lineNumber <= prev.lineNumber)) {
        throw ArgumentError(
          'Segments must be strictly ordered by page and line: segment[$i] (${curr.pageNumber}:${curr.lineNumber}) does not follow segment[${i - 1}] (${prev.pageNumber}:${prev.lineNumber}) for Ayah $id',
        );
      }
    }
  }

  int get surahNumber => id.surahNumber;
  int get ayahNumber => id.ayahNumber;

  /// Whether this Ayah spans across multiple lines.
  bool get isMultiLine => segments.length > 1;

  /// Whether this Ayah spans across multiple pages (for Madani 15-line, this is always false).
  bool get isMultiPage => pageNumber != endPageNumber;

  @override
  String toString() =>
      'QuranAyah($id, p.$pageNumber..$endPageNumber, ${segments.length} segments, $wordsCount words)';

  @override
  List<Object?> get props =>
      [id, pageNumber, endPageNumber, uthmaniText, wordsCount, segments];
}
