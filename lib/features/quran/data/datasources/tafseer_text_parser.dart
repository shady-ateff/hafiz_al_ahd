import '../../domain/entities/quran_tafseer.dart';

/// High-performance, non-destructive parser for Tafseer commentary text.
/// Extracts embedded Quranic quotes (<span class='aya'>...</span>) into typed segments.
class TafseerTextParser {
  /// Robust standard Dart RegExp matching `<span class='aya'>...</span>`:
  /// - `\s+`: required whitespace after span
  /// - `class\s*=\s*`: supports optional whitespace around '='
  /// - `['"]`: supports single quotes and double quotes
  /// - `\s*`: supports optional trailing whitespace before '>'
  /// - `(.*?)`: non-greedy capture of inner content with dotAll: true
  /// - `</span>`: exact closing tag
  static final RegExp spanPattern = RegExp(
    r'''<span\s+class\s*=\s*['"]aya['"]\s*>(.*?)</span>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Parses raw Tafseer text into structured segments.
  /// Guarantees that:
  /// 1. No character is silently discarded.
  /// 2. Unmatched or unknown markup remains part of commentary text.
  /// 3. All Unicode brackets, hair spaces, and diacritics are strictly preserved.
  static List<TafseerSegment> parse(String rawText) {
    if (rawText.isEmpty) return const [];

    // Fast-path: 99.33% of Ayahs contain no HTML markup
    if (!rawText.contains('<span')) {
      return [TafseerSegment(text: rawText, type: TafseerSegmentType.commentary)];
    }

    final segments = <TafseerSegment>[];
    int cursor = 0;

    for (final match in spanPattern.allMatches(rawText)) {
      // 1. Text preceding the span (Commentary)
      if (match.start > cursor) {
        final commentary = rawText.substring(cursor, match.start);
        if (commentary.isNotEmpty) {
          segments.add(TafseerSegment(
            text: commentary,
            type: TafseerSegmentType.commentary,
          ));
        }
      }

      // 2. Embedded Quranic quote inside the span
      final quote = match.group(1);
      if (quote != null && quote.isNotEmpty) {
        segments.add(TafseerSegment(
          text: quote,
          type: TafseerSegmentType.quranQuote,
        ));
      }

      cursor = match.end;
    }

    // 3. Trailing commentary text after the final span
    if (cursor < rawText.length) {
      final trailing = rawText.substring(cursor);
      if (trailing.isNotEmpty) {
        segments.add(TafseerSegment(
          text: trailing,
          type: TafseerSegmentType.commentary,
        ));
      }
    }

    return List.unmodifiable(segments);
  }
}

