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
  })  : assert(pageNumber >= 1 && pageNumber <= 604,
            'pageNumber must be between 1 and 604'),
        assert(endPageNumber >= pageNumber && endPageNumber <= 604,
            'endPageNumber must be >= pageNumber and <= 604'),
        assert(uthmaniText.isNotEmpty, 'uthmaniText cannot be empty'),
        assert(wordsCount > 0, 'wordsCount must be greater than 0'),
        assert(segments.isNotEmpty, 'segments cannot be empty'),
        segments = List.unmodifiable(segments);

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

