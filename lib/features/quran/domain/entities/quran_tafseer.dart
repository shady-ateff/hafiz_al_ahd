import 'package:equatable/equatable.dart';
import 'ayah_id.dart';

/// Semantic type of a Tafseer text segment.
enum TafseerSegmentType {
  /// General commentary and explanation text.
  commentary,

  /// Embedded Quranic quote or word reference extracted from semantic `<span class='aya'>` markup.
  quranQuote,
}

/// A parsed segment within a Tafseer commentary string.
class TafseerSegment extends Equatable {
  /// The literal text content of the segment.
  final String text;

  /// The semantic segment type.
  final TafseerSegmentType type;

  const TafseerSegment({
    required this.text,
    required this.type,
  });

  /// Convenience getter indicating whether this segment is an embedded Quranic quote.
  bool get isQuranQuote => type == TafseerSegmentType.quranQuote;

  @override
  List<Object?> get props => [text, type];

  @override
  String toString() => 'TafseerSegment(type: $type, text: "$text")';
}

/// Domain entity representing the complete Tafseer commentary for a single Ayah.
class QuranTafseer extends Equatable {
  /// Canonical identifier of the Ayah (e.g., "1:1", "2:255").
  final AyahId ayahId;

  /// The raw, unparsed Tafseer text as stored in the source dataset.
  final String rawText;

  /// Ordered, typed segments parsed from [rawText].
  final List<TafseerSegment> segments;

  /// The display name of the Tafseer edition (default: "التفسير الميسر").
  final String sourceName;

  const QuranTafseer({
    required this.ayahId,
    required this.rawText,
    required this.segments,
    this.sourceName = 'التفسير الميسر',
  });

  @override
  List<Object?> get props => [ayahId, rawText, segments, sourceName];

  @override
  String toString() =>
      'QuranTafseer(ayahId: ${ayahId.formatted}, sourceName: "$sourceName", segments: ${segments.length})';
}

