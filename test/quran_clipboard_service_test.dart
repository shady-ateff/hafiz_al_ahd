import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_clipboard_service.dart';

void main() {
  group('Phase 2.6.3.2 — QuranClipboardService Unit Tests', () {
    late QuranAyah ayahFatiha1;
    late QuranAyah ayahBaqarah255;
    late QuranAyah ayahIkhlas1;
    late QuranAyah ayahNas6;

    setUp(() {
      ayahFatiha1 = QuranAyah(
        id: AyahId(surahNumber: 1, ayahNumber: 1),
        pageNumber: 1,
        endPageNumber: 1,
        uthmaniText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
        wordsCount: 4,
        segments: [
          AyahSegment(
            ayahId: AyahId(surahNumber: 1, ayahNumber: 1),
            pageNumber: 1,
            lineNumber: 2,
            wordStart: 0,
            wordEnd: 3,
            qcfText: 'ﱁ ﱂ ﱃ ﱄ ﱅ',
          ),
        ],
      );

      ayahBaqarah255 = QuranAyah(
        id: AyahId(surahNumber: 2, ayahNumber: 255),
        pageNumber: 42,
        endPageNumber: 42,
        uthmaniText:
            'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ',
        wordsCount: 12,
        segments: [
          AyahSegment(
            ayahId: AyahId(surahNumber: 2, ayahNumber: 255),
            pageNumber: 42,
            lineNumber: 1,
            wordStart: 0,
            wordEnd: 11,
            qcfText: 'ﭐ ﭒ ﭓ ﭔ ﭕ ﭖ ﭗ ﭘ ﭙ ﭚ ﭛ ﭜ',
          ),
        ],
      );

      ayahIkhlas1 = QuranAyah(
        id: AyahId(surahNumber: 112, ayahNumber: 1),
        pageNumber: 604,
        endPageNumber: 604,
        uthmaniText: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
        wordsCount: 4,
        segments: [
          AyahSegment(
            ayahId: AyahId(surahNumber: 112, ayahNumber: 1),
            pageNumber: 604,
            lineNumber: 4,
            wordStart: 0,
            wordEnd: 3,
            qcfText: 'ﭑ ﭒ ﭓ ﭔ',
          ),
        ],
      );

      ayahNas6 = QuranAyah(
        id: AyahId(surahNumber: 114, ayahNumber: 6),
        pageNumber: 604,
        endPageNumber: 604,
        uthmaniText: 'مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ',
        wordsCount: 3,
        segments: [
          AyahSegment(
            ayahId: AyahId(surahNumber: 114, ayahNumber: 6),
            pageNumber: 604,
            lineNumber: 15,
            wordStart: 0,
            wordEnd: 2,
            qcfText: 'ﮊ ﮋ ﮌ',
          ),
        ],
      );
    });

    test('1. Correct formatting structure: brackets, newlines, and Surah/Ayah attribution', () {
      final formatted = QuranClipboardService.formatAyah(ayahFatiha1);

      const expected =
          '﴿ بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ﴾\n[سورة الفاتحة - الآية 1]';

      expect(formatted, equals(expected));
    });

    test('2. Complete preservation of Arabic unicode text and diacritics (tashkeel)', () {
      final formatted = QuranClipboardService.formatAyah(ayahBaqarah255);

      // Verify ornate brackets
      expect(formatted.startsWith('﴿ '), isTrue);
      expect(formatted.contains(' ﴾\n'), isTrue);

      // Verify exact Uthmani text with diacritics preserved
      expect(
        formatted.contains(
          'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ',
        ),
        isTrue,
      );

      // Verify attribution
      expect(formatted.endsWith('[سورة البقرة - الآية 255]'), isTrue);
    });

    test('3. Correct Surah names across beginning, middle, and end of the Quran', () {
      final fatihaFormatted = QuranClipboardService.formatAyah(ayahFatiha1);
      expect(fatihaFormatted, contains('[سورة الفاتحة - الآية 1]'));

      final baqarahFormatted = QuranClipboardService.formatAyah(ayahBaqarah255);
      expect(baqarahFormatted, contains('[سورة البقرة - الآية 255]'));

      final ikhlasFormatted = QuranClipboardService.formatAyah(ayahIkhlas1);
      expect(ikhlasFormatted, contains('[سورة الإخلاص - الآية 1]'));

      final nasFormatted = QuranClipboardService.formatAyah(ayahNas6);
      expect(nasFormatted, contains('[سورة الناس - الآية 6]'));
    });

    test('4. Complete exclusion of internal QCF glyphs and font codes', () {
      final formatted = QuranClipboardService.formatAyah(ayahFatiha1);

      for (final segment in ayahFatiha1.segments) {
        for (final qcfChar in segment.qcfText.split(' ')) {
          if (qcfChar.isNotEmpty) {
            expect(
              formatted.contains(qcfChar),
              isFalse,
              reason: 'Formatted text must not contain QCF glyph: $qcfChar',
            );
          }
        }
      }
    });

    test('5. copyAyah passes formatted text to clipboard setter and returns true on success', () async {
      ClipboardData? capturedData;
      final service = QuranClipboardService(
        clipboardSetter: (data) async {
          capturedData = data;
        },
      );

      final result = await service.copyAyah(ayahFatiha1);

      expect(result, isTrue);
      expect(capturedData, isNotNull);
      expect(
        capturedData!.text,
        equals(
          '﴿ بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ﴾\n[سورة الفاتحة - الآية 1]',
        ),
      );
    });

    test('6. copyAyah safely catches exceptions and returns false on failure without crashing', () async {
      final service = QuranClipboardService(
        clipboardSetter: (data) async {
          throw PlatformException(
            code: 'CLIPBOARD_ERROR',
            message: 'Clipboard access denied',
          );
        },
      );

      final result = await service.copyAyah(ayahFatiha1);

      expect(result, isFalse);
    });
  });
}

