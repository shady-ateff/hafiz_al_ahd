import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';

void main() {
  final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
  final ayah2 = AyahId(surahNumber: 1, ayahNumber: 2);
  const audioDefaultGreen = Color(0x382E7D32);
  const manualGold = AppColors.secondaryGold;

  final sampleLine = QuranLineMapping(
    pageNumber: 1,
    lineNumber: 2,
    words: [
      QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
        uthmaniText: 'بِسْمِ',
        qcfText: 'ﱁ',
      ),
      QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 2),
        uthmaniText: 'ٱللَّهِ',
        qcfText: 'ﱂ',
      ),
      QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 2, wordIndex: 1),
        uthmaniText: 'ٱلْحَمْدُ',
        qcfText: 'ﱃ',
      ),
      QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 2, wordIndex: 2),
        uthmaniText: 'لِلَّهِ',
        qcfText: 'ﱄ',
      ),
    ],
  );

  Widget buildWidget({
    AyahId? selectedAyahId,
    Color? highlightColor,
    AyahId? audioHighlightedAyahId,
    Color? audioHighlightColor,
    ValueChanged<QuranWord>? onWordTapped,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF_P001',
            dynamicHeight: 1.8,
            textColor: Colors.black,
            selectedAyahId: selectedAyahId,
            highlightColor: highlightColor,
            audioHighlightedAyahId: audioHighlightedAyahId,
            audioHighlightColor: audioHighlightColor,
            onWordTapped: onWordTapped,
          ),
        ),
      ),
    );
  }

  group('QuranInteractiveLineWidget Audio & Selection Decoupling (QA.4)', () {
    testWidgets('1. Only Audio Highlight active: matching words receive audio green highlight', (tester) async {
      await tester.pumpWidget(buildWidget(
        audioHighlightedAyahId: ayah1,
      ));
      await tester.pumpAndSettle();

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final textSpan = richText.text as TextSpan;
      final spans = textSpan.children!;

      // Word 0 (ayah1) -> highlighted with audioDefaultGreen
      expect(spans[0].style?.backgroundColor, equals(audioDefaultGreen));
      // Inter-word space between word 0 & word 1 (both ayah1) -> highlighted
      expect(spans[1].style?.backgroundColor, equals(audioDefaultGreen));
      // Word 1 (ayah1) -> highlighted with audioDefaultGreen
      expect(spans[2].style?.backgroundColor, equals(audioDefaultGreen));
      // Space between word 1 (ayah1) and word 2 (ayah2) -> null (different ayahs)
      expect(spans[3].style?.backgroundColor, isNull);
      // Word 2 (ayah2) -> null
      expect(spans[4].style?.backgroundColor, isNull);
    });

    testWidgets('2. Only Manual Selection active: matching words receive gold selection color', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedAyahId: ayah2,
        highlightColor: manualGold,
      ));
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = (richText.text as TextSpan).children!;

      // Word 0 & 1 (ayah1) -> null
      expect(spans[0].style?.backgroundColor, isNull);
      expect(spans[2].style?.backgroundColor, isNull);

      // Word 2 & 3 (ayah2) -> manualGold
      expect(spans[4].style?.backgroundColor, equals(manualGold));
      expect(spans[5].style?.backgroundColor, equals(manualGold)); // Inter-word space between 2 & 3
      expect(spans[6].style?.backgroundColor, equals(manualGold));
    });

    testWidgets('3. Overlap Priority: Manual Selection overrides Audio Highlight on the same Ayah', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedAyahId: ayah1,
        highlightColor: manualGold,
        audioHighlightedAyahId: ayah1,
        audioHighlightColor: audioDefaultGreen,
      ));
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = (richText.text as TextSpan).children!;

      // Both target ayah1: manual selection takes strict precedence
      expect(spans[0].style?.backgroundColor, equals(manualGold));
      expect(spans[1].style?.backgroundColor, equals(manualGold));
      expect(spans[2].style?.backgroundColor, equals(manualGold));

      // ayah2 words are unselected
      expect(spans[4].style?.backgroundColor, isNull);
      expect(spans[6].style?.backgroundColor, isNull);
    });

    testWidgets('4. Simultaneous distinct targets: Ayah 1 has Audio Highlight, Ayah 2 has Manual Selection', (tester) async {
      await tester.pumpWidget(buildWidget(
        selectedAyahId: ayah2,
        highlightColor: manualGold,
        audioHighlightedAyahId: ayah1,
        audioHighlightColor: audioDefaultGreen,
      ));
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = (richText.text as TextSpan).children!;

      // Word 0 & 1 (ayah1) -> audioDefaultGreen
      expect(spans[0].style?.backgroundColor, equals(audioDefaultGreen));
      expect(spans[1].style?.backgroundColor, equals(audioDefaultGreen));
      expect(spans[2].style?.backgroundColor, equals(audioDefaultGreen));

      // Boundary space -> null
      expect(spans[3].style?.backgroundColor, isNull);

      // Word 2 & 3 (ayah2) -> manualGold
      expect(spans[4].style?.backgroundColor, equals(manualGold));
      expect(spans[5].style?.backgroundColor, equals(manualGold));
      expect(spans[6].style?.backgroundColor, equals(manualGold));
    });

    testWidgets('5. Dynamic update from Ayah 1 to Ayah 2 smoothly updates spans', (tester) async {
      await tester.pumpWidget(buildWidget(
        audioHighlightedAyahId: ayah1,
      ));
      await tester.pumpAndSettle();

      var richText = tester.widget<RichText>(find.byType(RichText));
      var spans = (richText.text as TextSpan).children!;
      expect(spans[0].style?.backgroundColor, equals(audioDefaultGreen));
      expect(spans[4].style?.backgroundColor, isNull);

      // Audio progresses to Ayah 2
      await tester.pumpWidget(buildWidget(
        audioHighlightedAyahId: ayah2,
      ));
      await tester.pump();

      richText = tester.widget<RichText>(find.byType(RichText));
      spans = (richText.text as TextSpan).children!;
      expect(spans[0].style?.backgroundColor, isNull);
      expect(spans[4].style?.backgroundColor, equals(audioDefaultGreen));
    });
  });
}
