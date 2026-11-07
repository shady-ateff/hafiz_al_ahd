import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/tafseer_text_parser.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_tafseer.dart';

void main() {
  group('TafseerTextParser Unit Tests', () {
    test('1. Plain text without spans returns a single commentary segment', () {
      const text = 'تفسير بسيط بدون أي شواهد قرآنية أو وسوم.';
      final segments = TafseerTextParser.parse(text);

      expect(segments.length, equals(1));
      expect(segments.first.type, equals(TafseerSegmentType.commentary));
      expect(segments.first.text, equals(text));
      expect(segments.first.isQuranQuote, isFalse);
    });

    test('2. Empty string returns empty list', () {
      final segments = TafseerTextParser.parse('');
      expect(segments, isEmpty);
    });

    test('3. Single span with single quotes extracts commentary and quote segments', () {
      const text = "بداية التفسير <span class='aya'>ﵡاهدِنَا الصِّرَاطَﵠ</span> ونهاية التفسير.";
      final segments = TafseerTextParser.parse(text);

      expect(segments.length, equals(3));
      expect(segments[0].type, equals(TafseerSegmentType.commentary));
      expect(segments[0].text, equals('بداية التفسير '));

      expect(segments[1].type, equals(TafseerSegmentType.quranQuote));
      expect(segments[1].text, equals('ﵡاهدِنَا الصِّرَاطَﵠ'));
      expect(segments[1].isQuranQuote, isTrue);

      expect(segments[2].type, equals(TafseerSegmentType.commentary));
      expect(segments[2].text, equals(' ونهاية التفسير.'));
    });

    test('4. Double quotes match <span class="aya">', () {
      const text = 'نص قبل <span class="aya">ﵡآيةﵠ</span> نص بعد';
      final segments = TafseerTextParser.parse(text);

      expect(segments.length, equals(3));
      expect(segments[1].type, equals(TafseerSegmentType.quranQuote));
      expect(segments[1].text, equals('ﵡآيةﵠ'));
    });

    test('5. Whitespace variations around equals sign', () {
      const variations = [
        "<span class = 'aya'>ﵡنصﵠ</span>",
        "<span class= 'aya'>ﵡنصﵠ</span>",
        "<span class ='aya'>ﵡنصﵠ</span>",
        '<span  class = "aya" >ﵡنصﵠ</span>',
      ];

      for (final v in variations) {
        final segments = TafseerTextParser.parse(v);
        expect(segments.length, equals(1), reason: 'Failed for variation: $v');
        expect(segments[0].type, equals(TafseerSegmentType.quranQuote));
        expect(segments[0].text, equals('ﵡنصﵠ'));
      }
    });

    test('6. Multiple spans in single commentary (Ayah 1:1 format)', () {
      const ayah11 =
          "[1] أبتدئ قراءة القرآن باسم الله مستعيناً به، <span class='aya'>ﵡ ٱللَّهِﵠ</span> علم على الرب -تبارك وتعالى- المعبود بحق دون سواه، وهو أخص أسماء الله تعالى، ولا يسمى به غيره سبحانه.<span class='aya'>ﵡٱلرَّحۡمَٰنِﵠ</span> ذي الرحمة العامة الذي وسعت رحمته جميع الخلق، <span class='aya'>ﵡٱلرَّحِيمِﵠ</span> بالمؤمنين، وهما اسمان من أسمائه تعالى، يتضمنان إثبات صفة الرحمة لله تعالى، كما يليق بجلاله.";

      final segments = TafseerTextParser.parse(ayah11);

      expect(segments.length, equals(7));
      expect(segments[0].type, equals(TafseerSegmentType.commentary));
      expect(segments[1].type, equals(TafseerSegmentType.quranQuote));
      expect(segments[1].text, equals('ﵡ ٱللَّهِﵠ'));

      expect(segments[2].type, equals(TafseerSegmentType.commentary));
      expect(segments[3].type, equals(TafseerSegmentType.quranQuote));
      expect(segments[3].text, equals('ﵡٱلرَّحۡمَٰنِﵠ'));

      expect(segments[4].type, equals(TafseerSegmentType.commentary));
      expect(segments[5].type, equals(TafseerSegmentType.quranQuote));
      expect(segments[5].text, equals('ﵡٱلرَّحِيمِﵠ'));

      expect(segments[6].type, equals(TafseerSegmentType.commentary));
      expect(segments[6].text.startsWith(' بالمؤمنين'), isTrue);
    });

    test('7. Preserves Unicode brackets U+FD61/U+FD60 and Hair Space U+200A exactly', () {
      const quote = 'ﵡ ٱللَّهِﵠ';
      const text = "<span class='aya'>$quote</span>";
      final segments = TafseerTextParser.parse(text);

      expect(segments.length, equals(1));
      expect(segments[0].text, equals(quote));
      expect(segments[0].text.codeUnits.contains(0x200A), isTrue); // Hair Space
      expect(segments[0].text.codeUnits.contains(0xFD61), isTrue); // ﵡ
      expect(segments[0].text.codeUnits.contains(0xFD60), isTrue); // ﵠ
    });

    test('8. Unmatched opening tag is NOT discarded; preserved as commentary', () {
      const input = "نص مع وسم غير مغلق <span class='aya'>نص الآية وباقي الكلام";
      final segments = TafseerTextParser.parse(input);

      expect(segments.length, equals(1));
      expect(segments[0].type, equals(TafseerSegmentType.commentary));
      expect(segments[0].text, equals(input));
    });

    test('9. Orphan closing tag is NOT discarded; preserved as commentary', () {
      const input = "نص مع إغلاق فقط </span> نهاية النص";
      final segments = TafseerTextParser.parse(input);

      expect(segments.length, equals(1));
      expect(segments[0].type, equals(TafseerSegmentType.commentary));
      expect(segments[0].text, equals(input));
    });

    test('10. Unknown tag (e.g. <div>) is NOT treated as quote span; preserved in commentary', () {
      const input = "نص <div class='note'>ملاحظة</div> ختام";
      final segments = TafseerTextParser.parse(input);

      expect(segments.length, equals(1));
      expect(segments[0].type, equals(TafseerSegmentType.commentary));
      expect(segments[0].text, equals(input));
    });

    test('11. Full reconstruction equality: concatenated segments match stripped text', () {
      const testCases = [
        "[1] أبتدئ قراءة القرآن باسم الله مستعيناً به، <span class='aya'>ﵡ ٱللَّهِﵠ</span> علم على الرب.",
        "<span class='aya'>ﵡالٓمٓ ﵠ</span> هذه الحروف وغيرها.",
        "ويستحب للقارئ أن يقول في الصلاة بعد قراءة الفاتحة: <span class='aya'>ﵡآمينﵠ</span>، ومعناها: اللهم استجب.",
      ];

      for (final tc in testCases) {
        final segments = TafseerTextParser.parse(tc);
        final reconstructed = segments.map((s) => s.text).join();
        final expected = tc.replaceAllMapped(TafseerTextParser.spanPattern, (m) => m.group(1)!);
        expect(reconstructed, equals(expected));
      }
    });
  });
}

