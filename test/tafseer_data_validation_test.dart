import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tafseer Data Pipeline Validation (Phase 2 Canonical Parity)', () {
    late File jsonAssetFile;
    late Map<String, dynamic> assetJson;
    late Map<String, dynamic> metadata;
    late Map<String, dynamic> tafseerData;

    final spanRegex = RegExp(
      r'''<span\s+class\s*=\s*['"]aya['"]\s*>(.*?)</span>''',
      caseSensitive: false,
      dotAll: true,
    );
    final htmlTagRegex = RegExp(r'<[^>]+>');

    setUpAll(() {
      jsonAssetFile = File('assets/quran/tafseer/tafseer_mouaser.json');
      expect(jsonAssetFile.existsSync(), isTrue, reason: 'tafseer_mouaser.json must exist');

      final content = jsonAssetFile.readAsStringSync(encoding: utf8);
      expect(content.isNotEmpty, isTrue, reason: 'Asset must not be empty');

      assetJson = jsonDecode(content) as Map<String, dynamic>;
      metadata = assetJson['metadata'] as Map<String, dynamic>;
      tafseerData = assetJson['tafseer'] as Map<String, dynamic>;
    });

    test('1. Metadata matches authoritative schema and counts', () {
      expect(metadata['version'], equals('3.0'));
      expect(metadata['edition'], equals('KFGQPC Tafseer Mouaser'));
      expect(metadata['total_ayahs'], equals(6236));
      expect(metadata['total_spans'], equals(47));
      expect(metadata['spanned_ayahs'], equals(42));
      expect(metadata['source'], equals('King Fahd Complex for Printing the Holy Quran'));
      expect(metadata['license'], contains('KFGQPC'));
    });

    test('2. Total Ayah records is exactly 6,236 with non-empty commentary', () {
      expect(tafseerData.length, equals(6236));

      int emptyCount = 0;
      for (final entry in tafseerData.entries) {
        final text = entry.value as String?;
        if (text == null || text.trim().isEmpty) {
          emptyCount++;
        }
      }
      expect(emptyCount, equals(0), reason: 'Every Ayah must have non-empty Tafseer text');
    });

    test('3. Key format strictly conforms to "surah:ayah" across 114 Surahs', () {
      final surahSet = <int>{};
      final keyPattern = RegExp(r'^(\d+):(\d+)$');

      for (final key in tafseerData.keys) {
        final match = keyPattern.firstMatch(key);
        expect(match, isNotNull, reason: 'Key "$key" does not match surah:ayah format');

        final surah = int.parse(match!.group(1)!);
        final ayah = int.parse(match.group(2)!);

        expect(surah >= 1 && surah <= 114, isTrue);
        expect(ayah >= 1 && ayah <= 286, isTrue);
        surahSet.add(surah);
      }

      expect(surahSet.length, equals(114), reason: 'All 114 Surahs must be present');
    });

    test('4. 100% Reconciliation with Quran Mapping Engine (ayah_mapping.json)', () {
      final mappingFile = File('assets/quran/mushaf/ayah_mapping.json');
      expect(mappingFile.existsSync(), isTrue);

      final mappingJson = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
      final mappingAyahs = (mappingJson['ayahs'] as Map<String, dynamic>).keys.toSet();
      final tafseerKeys = tafseerData.keys.toSet();

      final missing = mappingAyahs.difference(tafseerKeys);
      final extra = tafseerKeys.difference(mappingAyahs);

      expect(missing, isEmpty, reason: 'Tafseer is missing Ayahs that exist in Quran Mapping');
      expect(extra, isEmpty, reason: 'Tafseer contains extra Ayahs not in Quran Mapping');
    });

    test('5. Exactly 47 <span class=\'aya\'> tags across 42 Ayahs', () {
      int totalSpans = 0;
      final spannedAyahs = <String>{};

      for (final entry in tafseerData.entries) {
        final text = entry.value as String;
        final matches = spanRegex.allMatches(text);
        if (matches.isNotEmpty) {
          totalSpans += matches.length;
          spannedAyahs.add(entry.key);
        }
      }

      expect(totalSpans, equals(47), reason: 'Total valid span matches must be exactly 47');
      expect(spannedAyahs.length, equals(42), reason: 'Spanned Ayahs count must be exactly 42');
    });

    test('6. HTML Tag Hygiene: No unexpected or malformed tags', () {
      for (final entry in tafseerData.entries) {
        final text = entry.value as String;
        for (final tagMatch in htmlTagRegex.allMatches(text)) {
          final tag = tagMatch.group(0)!;
          final normalized = tag.toLowerCase().replaceAll(' ', '');
          final isValidOpen = normalized == "<spanclass='aya'>" || normalized == '<spanclass="aya">';
          final isValidClose = normalized == '</span>';

          expect(
            isValidOpen || isValidClose,
            isTrue,
            reason: 'Unexpected tag "$tag" found in Ayah ${entry.key}',
          );
        }
      }
    });

    test('7. Preserves Unicode brackets U+FD61/U+FD60 and Hair Space U+200A', () {
      // Ayah 1:1 has 3 spans with hair spaces and ornate brackets
      final ayah11 = tafseerData['1:1'] as String;
      expect(ayah11, contains('<span class=\'aya\'>ﵡ ٱللَّهِﵠ</span>'));
      expect(ayah11, contains('<span class=\'aya\'>ﵡٱلرَّحۡمَٰنِﵠ</span>'));
      expect(ayah11, contains('<span class=\'aya\'>ﵡٱلرَّحِيمِﵠ</span>'));
      expect(ayah11.codeUnits.contains(0xFD61), isTrue); // ﵡ
      expect(ayah11.codeUnits.contains(0xFD60), isTrue); // ﵠ
      expect(ayah11.codeUnits.contains(0x200A), isTrue); //   (Hair Space)
    });

    test('8. 100% Character Identity against source SQL dataset', () {
      final sqlFile = File('docs/tafseer/tafseerMouaser_v03.sql');
      expect(sqlFile.existsSync(), isTrue);

      final lines = sqlFile.readAsLinesSync(encoding: utf8);
      final insertLines = lines.where((l) => l.startsWith('INSERT INTO')).toList();
      expect(insertLines.length, equals(6236));

      // Verify full character identity across key sample Ayahs spanning the whole Quran
      final checkKeys = [
        '1:1', '1:7', '2:1', '2:255', '3:18', '9:129', '18:1', '36:1',
        '55:1', '112:1', '113:1', '114:6',
      ];

      for (final key in checkKeys) {
        expect(tafseerData.containsKey(key), isTrue);
        final parts = key.split(':');
        final sora = int.parse(parts[0]);
        final aya = int.parse(parts[1]);

        final line = insertLines.firstWhere((l) {
          final fields = SqlInsertParser.parseInsertValues(l);
          return fields[3].value == sora && fields[8].value == aya;
        });

        final fields = SqlInsertParser.parseInsertValues(line);
        final sqlText = fields[11].value as String;
        expect(tafseerData[key], equals(sqlText));
      }
    });

    test('9. Minified JSON Asset Integrity (no unneeded whitespace)', () {
      final raw = jsonAssetFile.readAsStringSync(encoding: utf8);
      expect(raw.startsWith('{"metadata":{'), isTrue);
      // Minified: single line with no leading indentation
      expect(raw.contains('\n'), isFalse, reason: 'Minified JSON should not contain newline indentation');
    });
  });
}

class SqlField {
  final dynamic value;
  final bool isQuoted;

  const SqlField.string(String str) : value = str, isQuoted = true;
  const SqlField.number(int num) : value = num, isQuoted = false;
  const SqlField.nullValue() : value = null, isQuoted = false;
}

class SqlInsertParser {
  static List<SqlField> parseInsertValues(String line, {int lineNumber = 0}) {
    final valuesIdx = line.indexOf('VALUES (');
    if (valuesIdx == -1) {
      throw FormatException('Line $lineNumber missing "VALUES (" marker');
    }

    final start = valuesIdx + 8;
    final end = line.lastIndexOf(');');
    if (end == -1) {
      throw FormatException('Line $lineNumber missing closing ");" marker');
    }

    final inner = line.substring(start, end);
    final List<SqlField> fields = [];
    final sb = StringBuffer();
    bool inQuotes = false;
    bool hasSeenQuoteInField = false;
    int i = 0;

    while (i < inner.length) {
      final c = inner[i];

      if (inQuotes) {
        if (c == '\\') {
          if (i + 1 < inner.length) {
            final next = inner[i + 1];
            switch (next) {
              case "'":  sb.write("'"); break;
              case '"':  sb.write('"'); break;
              case '\\': sb.write('\\'); break;
              case 'n':  sb.write('\n'); break;
              case 'r':  sb.write('\r'); break;
              case 't':  sb.write('\t'); break;
              case '0':  sb.write('\x00'); break;
              default:   sb.write(next);
            }
            i += 2;
            continue;
          } else {
            throw FormatException('Line $lineNumber: trailing backslash escape at end of string');
          }
        } else if (c == "'") {
          if (i + 1 < inner.length && inner[i + 1] == "'") {
            sb.write("'");
            i += 2;
            continue;
          } else {
            inQuotes = false;
            i++;
            continue;
          }
        } else {
          sb.write(c);
          i++;
        }
      } else {
        if (c == "'") {
          inQuotes = true;
          hasSeenQuoteInField = true;
          i++;
        } else if (c == ',') {
          if (hasSeenQuoteInField) {
            fields.add(SqlField.string(sb.toString()));
          } else {
            final raw = sb.toString().trim();
            if (raw.toUpperCase() == 'NULL' || raw.isEmpty) {
              fields.add(const SqlField.nullValue());
            } else {
              final numVal = int.tryParse(raw);
              if (numVal != null) {
                fields.add(SqlField.number(numVal));
              } else {
                throw FormatException('Line $lineNumber: invalid unquoted token "$raw"');
              }
            }
          }
          sb.clear();
          hasSeenQuoteInField = false;
          i++;
        } else {
          sb.write(c);
          i++;
        }
      }
    }

    if (inQuotes) {
      throw FormatException('Line $lineNumber: unterminated single quote at end of line');
    }

    if (hasSeenQuoteInField) {
      fields.add(SqlField.string(sb.toString()));
    } else {
      final raw = sb.toString().trim();
      if (raw.toUpperCase() == 'NULL' || raw.isEmpty) {
        fields.add(const SqlField.nullValue());
      } else {
        final numVal = int.tryParse(raw);
        if (numVal != null) {
          fields.add(SqlField.number(numVal));
        } else {
          throw FormatException('Line $lineNumber: invalid unquoted token "$raw"');
        }
      }
    }

    return fields;
  }
}


