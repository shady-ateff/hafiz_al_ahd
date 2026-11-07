import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quran Ayah Mapping Engine Tests (Phase 1 Canonical Parity)', () {
    late Map<String, dynamic> mappingData;
    late List<dynamic> appLinesData;

    setUpAll(() {
      final mappingFile = File('assets/quran/mushaf/ayah_mapping.json');
      expect(mappingFile.existsSync(), isTrue, reason: 'ayah_mapping.json must exist');
      mappingData = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;

      final appLinesFile = File('assets/quran/mushaf/quran_lines.json');
      expect(appLinesFile.existsSync(), isTrue, reason: 'quran_lines.json must exist');
      appLinesData = jsonDecode(appLinesFile.readAsStringSync()) as List<dynamic>;
    });

    test('Metadata reflects complete 114 Surahs, 6236 Ayahs, 604 Pages', () {
      final metadata = mappingData['metadata'] as Map<String, dynamic>;
      expect(metadata['total_surahs'], equals(114));
      expect(metadata['total_ayahs'], equals(6236));
      expect(metadata['total_pages'], equals(604));
      expect(metadata['total_text_lines'], equals(8820));
      expect(metadata['total_words'], equals(78003));
      expect(metadata['total_qcf_tokens'], equals(83863));
    });

    test('All 114 Surahs and 6236 Ayahs exist with valid Uthmani text', () {
      final ayahs = mappingData['ayahs'] as Map<String, dynamic>;
      expect(ayahs.length, equals(6236));

      final Set<int> surahs = {};
      int missingUthmaniCount = 0;

      ayahs.forEach((key, value) {
        final ayah = value as Map<String, dynamic>;
        final surah = ayah['surah'] as int;
        final ayahNum = ayah['ayah'] as int;
        final uthmani = ayah['uthmani'] as String?;
        final page = ayah['page'] as int;
        final endPage = ayah['end_page'] as int;

        expect(key, equals('$surah:$ayahNum'));
        surahs.add(surah);

        if (uthmani == null || uthmani.trim().isEmpty) {
          missingUthmaniCount++;
        }

        expect(page >= 1 && page <= 604, isTrue);
        expect(endPage >= page && endPage <= 604, isTrue);
        expect((ayah['segments'] as List).isNotEmpty, isTrue);
      });

      expect(surahs.length, equals(114));
      expect(missingUthmaniCount, equals(0));
    });

    test('All 604 Pages match quran_lines.json with 0 unmatched QCF tokens', () {
      final pages = mappingData['pages'] as Map<String, dynamic>;
      expect(pages.length, equals(604));

      int unmatchedTokens = 0;

      for (int p = 1; p <= 604; p++) {
        final pageLines = pages['$p'] as List<dynamic>;
        final appPage = appLinesData[p - 1] as Map<String, dynamic>;
        final appLines = appPage['lines'] as List<dynamic>;

        expect(pageLines.length, equals(appLines.length),
            reason: 'Line count mismatch on page $p');

        for (int l = 0; l < pageLines.length; l++) {
          final mapLine = pageLines[l] as Map<String, dynamic>;
          final appLine = appLines[l] as Map<String, dynamic>;

          final mapText = (mapLine['text'] as String).trim();
          final appText = (appLine['text'] as String).trim();

          if (mapText != appText) {
            unmatchedTokens++;
          }

          final words = mapLine['words'] as List<dynamic>;
          final List<String> mapTokens = [];
          for (var w in words) {
            final qcf = (w['qcf'] as String).trim();
            mapTokens.addAll(qcf.split(RegExp(r'\s+')));
          }

          final List<String> appTokens = appText.split(RegExp(r'\s+'));
          if (mapTokens.length != appTokens.length) {
            unmatchedTokens += (mapTokens.length - appTokens.length).abs();
          } else {
            for (int t = 0; t < mapTokens.length; t++) {
              if (mapTokens[t] != appTokens[t]) {
                unmatchedTokens++;
              }
            }
          }
        }
      }

      expect(unmatchedTokens, equals(0));
    });

    test('Sample Ayah Verification: Al-Fatihah 1:1, Al-Baqarah 2:255, An-Nas 114:6', () {
      final ayahs = mappingData['ayahs'] as Map<String, dynamic>;

      // 1:1
      final fatihah1 = ayahs['1:1'] as Map<String, dynamic>;
      expect(fatihah1['surah'], equals(1));
      expect(fatihah1['ayah'], equals(1));
      expect(fatihah1['page'], equals(1));
      expect(fatihah1['uthmani'], contains('بِسۡمِ ٱللَّهِ'));

      // 2:255
      final kursi = ayahs['2:255'] as Map<String, dynamic>;
      expect(kursi['surah'], equals(2));
      expect(kursi['ayah'], equals(255));
      expect(kursi['page'], equals(42));
      expect(kursi['uthmani'], contains('ٱللَّهُ لَاۤ إِلَـٰهَ إِلَّا هُوَ ٱلۡحَیُّ ٱلۡقَیُّومُ'));

      // 114:6
      final nas6 = ayahs['114:6'] as Map<String, dynamic>;
      expect(nas6['surah'], equals(114));
      expect(nas6['ayah'], equals(6));
      expect(nas6['page'], equals(604));
      expect(nas6['uthmani'], equals('مِنَ ٱلۡجِنَّةِ وَٱلنَّاسِ'));
    });
  });
}

