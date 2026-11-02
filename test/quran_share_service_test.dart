import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  group('Phase 2.6.3.3 — QuranShareService Unit Tests', () {
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

    test('1. Exact canonical share format with double line breaks and Hafiz Al-Ahd attribution', () {
      final formatted = QuranShareService.formatAyahForShare(ayahFatiha1);

      const expected =
          '﴿ بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ﴾\n\n'
          '[سورة الفاتحة - الآية 1]\n\n'
          'مشاركة من تطبيق حافظ العهد';

      expect(formatted, equals(expected));
    });

    test('2. Complete preservation of Arabic diacritics and Uthmani orthography', () {
      final formatted = QuranShareService.formatAyahForShare(ayahBaqarah255);

      expect(
        formatted.contains(
          'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ',
        ),
        isTrue,
      );
      expect(formatted, contains('[سورة البقرة - الآية 255]'));
      expect(formatted, endsWith('مشاركة من تطبيق حافظ العهد'));
    });

    test('3. Correct Surah resolution across early, middle, and late Surahs', () {
      final fatiha = QuranShareService.formatAyahForShare(ayahFatiha1);
      expect(fatiha, contains('سورة الفاتحة'));

      final baqarah = QuranShareService.formatAyahForShare(ayahBaqarah255);
      expect(baqarah, contains('سورة البقرة'));

      final ikhlas = QuranShareService.formatAyahForShare(ayahIkhlas1);
      expect(ikhlas, contains('سورة الإخلاص'));

      final nas = QuranShareService.formatAyahForShare(ayahNas6);
      expect(nas, contains('سورة الناس'));
    });

    test('4. Absolute exclusion of font-specific QCF glyphs', () {
      final formatted = QuranShareService.formatAyahForShare(ayahFatiha1);

      for (final segment in ayahFatiha1.segments) {
        for (final qcfChar in segment.qcfText.split(' ')) {
          if (qcfChar.isNotEmpty) {
            expect(
              formatted.contains(qcfChar),
              isFalse,
              reason: 'QCF page font character must never be in shared text: $qcfChar',
            );
          }
        }
      }
    });

    test('5. shareText invokes platform runner and returns success on completed share', () async {
      String? capturedText;
      String? capturedSubject;

      final service = QuranShareService(
        textShare: (text, {subject}) async {
          capturedText = text;
          capturedSubject = subject;
          return const ShareResult('com.whatsapp', ShareResultStatus.success);
        },
      );

      final status = await service.shareText(ayahFatiha1);

      expect(status, equals(ShareResultStatus.success));
      expect(capturedText, equals(QuranShareService.formatAyahForShare(ayahFatiha1)));
      expect(capturedSubject, contains('سورة الفاتحة'));
    });

    test('6. shareText returns dismissed when user cancels the native share sheet', () async {
      final service = QuranShareService(
        textShare: (text, {subject}) async {
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );

      final status = await service.shareText(ayahFatiha1);

      expect(status, equals(ShareResultStatus.dismissed));
    });

    test('7. shareText catches exceptions and returns unavailable without throwing', () async {
      final service = QuranShareService(
        textShare: (text, {subject}) async {
          throw Exception('Share channel failed');
        },
      );

      final status = await service.shareText(ayahFatiha1);

      expect(status, equals(ShareResultStatus.unavailable));
    });

    test('8. shareImageFile invokes platform runner with XFile and returns success', () async {
      List<XFile>? capturedFiles;
      String? capturedSubject;

      final service = QuranShareService(
        filesShare: (files, {text, subject}) async {
          capturedFiles = files;
          capturedSubject = subject;
          return const ShareResult('com.telegram', ShareResultStatus.success);
        },
      );

      final status = await service.shareImageFile('/tmp/test_card.png', ayahFatiha1);

      expect(status, equals(ShareResultStatus.success));
      expect(capturedFiles, isNotNull);
      expect(capturedFiles!.first.path, equals('/tmp/test_card.png'));
      expect(capturedSubject, contains('سورة الفاتحة'));
    });

    test('9. shareImageFile catches exceptions and returns unavailable without throwing', () async {
      final service = QuranShareService(
        filesShare: (files, {text, subject}) async {
          throw Exception('Image share failed');
        },
      );

      final status = await service.shareImageFile('/tmp/test_card.png', ayahFatiha1);

      expect(status, equals(ShareResultStatus.unavailable));
    });
  });
}

