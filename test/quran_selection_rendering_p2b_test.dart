import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_page_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranMappingRepositoryImpl repository;
  late Map<int, QuranPage> allPages;
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerSingleton<SharedPreferences>(prefs);
    }

    final dataSource = QuranMappingLocalDataSourceImpl(
      customDataLoader: () async =>
          File('assets/quran/mushaf/ayah_mapping.json').readAsString(),
    );
    repository = QuranMappingRepositoryImpl(localDataSource: dataSource);
    await repository.init();

    final rawLinesJson =
        File('assets/quran/mushaf/quran_lines.json').readAsStringSync();
    final List<dynamic> decodedPages = jsonDecode(rawLinesJson);
    allPages = {};
    for (final pageObj in decodedPages) {
      final int pageNum = pageObj['page_number'] as int;
      final linesList = pageObj['lines'] as List<dynamic>;
      final lines = linesList
          .map((l) => QuranLine(
                lineNumber: l['line_number'] as int,
                surahNumber: l['surah_number'] as int,
                text: l['text'].toString().trim(),
              ))
          .toList();
      allPages[pageNum] = QuranPage(pageNumber: pageNum, lines: lines);
    }
  });

  Widget buildPageHarness({
    required int pageNumber,
    required AyahId? selectedAyahId,
    ValueChanged<QuranWord>? onWordTapped,
    ValueChanged<QuranWord>? onWordLongPressed,
  }) {
    final page = allPages[pageNumber]!;
    final mappings = repository.getPageMapping(pageNumber);

    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<QuranSettingsCubit>(
          create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
          child: FutureBuilder(
            future: mappings,
            builder: (context, snapshot) {
              final lines = snapshot.data?.getOrElse(() => []) ?? [];
              return QuranPageWidget(
                page: page,
                isFontLoaded: true,
                lineMappings: lines,
                selectedAyahId: selectedAyahId,
                onWordTapped: onWordTapped,
                onWordLongPressed: onWordLongPressed,
              );
            },
          ),
        ),
      ),
    );
  }

  List<RichText> getLineRichTexts(WidgetTester tester) {
    return tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(QuranInteractiveLineWidget),
            matching: find.byType(RichText),
          ),
        )
        .toList();
  }

  group('Phase P2-B: Quran Selection Rendering Tests', () {
    testWidgets('1. Selecting an Ayah: Applies highlight to exact words on target line',
        (tester) async {
      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1); // "الم" on Page 2, Line 1

      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah1),
      );
      await tester.pumpAndSettle();

      final lineRichTexts = getLineRichTexts(tester);
      expect(lineRichTexts, isNotEmpty);

      // Line 1 should have highlighted text span
      final line1Spans = (lineRichTexts[0].text as TextSpan).children!;
      final wordSpan = line1Spans[0] as TextSpan;
      expect(wordSpan.style?.backgroundColor, isNotNull,
          reason: 'Selected word on Line 1 must receive highlight color');

      // Line 2 should have unhighlighted text span
      final line2Spans = (lineRichTexts[1].text as TextSpan).children!;
      for (final span in line2Spans.whereType<TextSpan>()) {
        expect(span.style?.backgroundColor, isNull,
            reason: 'Unaffected line words must remain unhighlighted');
      }
    });

    testWidgets('2. Deselecting an Ayah: Removes highlight cleanly without leaving artifacts',
        (tester) async {
      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1);

      // Step A: Selected
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah1),
      );
      await tester.pumpAndSettle();

      // Step B: Deselected (null)
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: null),
      );
      await tester.pumpAndSettle();

      final lineRichTexts = getLineRichTexts(tester);
      for (final rt in lineRichTexts) {
        final root = rt.text as TextSpan;
        if (root.children != null) {
          for (final span in root.children!.whereType<TextSpan>()) {
            expect(span.style?.backgroundColor, isNull,
                reason: 'Deselected page must have zero highlighted spans');
          }
        }
      }
    });

    testWidgets('3. Switching Selection Between Ayahs: Smoothly transitions highlight',
        (tester) async {
      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1); // Line 1
      final ayah2 = AyahId(surahNumber: 2, ayahNumber: 2); // Line 1 (latter part) or Line 2

      // Render with Ayah 1
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah1),
      );
      await tester.pumpAndSettle();

      // Switch to Ayah 2
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah2),
      );
      await tester.pumpAndSettle();

      final lineRichTexts = getLineRichTexts(tester);
      expect(lineRichTexts, isNotEmpty);

      // Verify that Ayah 1 word ("الم") is no longer highlighted
      final line1Spans = (lineRichTexts[0].text as TextSpan).children!;
      final word1 = line1Spans[0] as TextSpan;
      expect(word1.style?.backgroundColor, isNull,
          reason: 'Previously selected Ayah must lose its highlight');
    });

    testWidgets('4. Selection Changes Across Different Lines: Multi-line Ayah 2:5 spans lines 4 & 5',
        (tester) async {
      final ayah5 = AyahId(surahNumber: 2, ayahNumber: 5);

      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah5),
      );
      await tester.pumpAndSettle();

      final lineWidgets = tester
          .widgetList<QuranInteractiveLineWidget>(find.byType(QuranInteractiveLineWidget))
          .toList();

      final linesWithAyah5 = lineWidgets
          .where((lw) => lw.line.words.any((w) => w.ayahId == ayah5))
          .toList();

      expect(linesWithAyah5.length, greaterThanOrEqualTo(2),
          reason: 'Ayah 2:5 is a multi-line Ayah spanning across lines on Page 2');

      for (final lineWidget in linesWithAyah5) {
        final lineFinder = find.byWidget(lineWidget);
        final richText = tester.widget<RichText>(
          find.descendant(of: lineFinder, matching: find.byType(RichText)),
        );
        final spans = (richText.text as TextSpan).children!;
        final hasHighlight = spans.whereType<TextSpan>().any((s) => s.style?.backgroundColor != null);
        expect(hasHighlight, isTrue, reason: 'Line ${lineWidget.line.lineNumber} must contain highlighted words');
      }

      // Unrelated lines (e.g. Line 1) must not be highlighted
      final firstLineFinder = find.byWidget(lineWidgets.first);
      final firstRichText = tester.widget<RichText>(
        find.descendant(of: firstLineFinder, matching: find.byType(RichText)),
      );
      final line1Spans = (firstRichText.text as TextSpan).children!;
      for (final span in line1Spans.whereType<TextSpan>()) {
        expect(span.style?.backgroundColor, isNull);
      }
    });

    testWidgets('5. Selection Remains Correct After Page Changes', (tester) async {
      final ayah11 = AyahId(surahNumber: 1, ayahNumber: 1); // Page 1

      // Render on Page 1 with selection
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 1, selectedAyahId: ayah11),
      );
      await tester.pumpAndSettle();

      // Navigate to Page 2 (different page, same or cleared selection)
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: null),
      );
      await tester.pumpAndSettle();

      // Navigate back to Page 1 with selection restored
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 1, selectedAyahId: ayah11),
      );
      await tester.pumpAndSettle();

      final lineRichTexts = getLineRichTexts(tester);
      final line1Spans = (lineRichTexts[0].text as TextSpan).children!;
      final hasHighlight = line1Spans
          .whereType<TextSpan>()
          .any((s) => s.style?.backgroundColor != null);
      expect(hasHighlight, isTrue,
          reason: 'Selection must restore and render correctly when returning to the page');
    });

    testWidgets('6. Gesture Behavior: Recognizers route taps and long-presses accurately',
        (tester) async {
      QuranWord? tappedWord;
      QuranWord? longPressedWord;

      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1);

      await tester.pumpWidget(
        buildPageHarness(
          pageNumber: 2,
          selectedAyahId: ayah1,
          onWordTapped: (w) => tappedWord = w,
          onWordLongPressed: (w) => longPressedWord = w,
        ),
      );
      await tester.pumpAndSettle();

      final lineRichTexts = getLineRichTexts(tester);
      final spans = (lineRichTexts[0].text as TextSpan).children!;
      final firstWordSpan = spans[0] as TextSpan;

      // Word 1 (Alif-Lam-Mim) belongs to selected Ayah 2:1 -> uses QuranWordTapGestureRecognizer
      expect(firstWordSpan.recognizer, isA<QuranWordTapGestureRecognizer>());
      final tapRecognizer = firstWordSpan.recognizer as QuranWordTapGestureRecognizer;

      // Simulate Tap
      tapRecognizer.onTap?.call();
      expect(tappedWord, isNotNull);
      expect(tappedWord!.location.ayahNumber, equals(1));

      // Simulate Long Press
      tapRecognizer.onLongPress?.call();
      expect(longPressedWord, isNotNull);
      expect(longPressedWord!.location.ayahNumber, equals(1));
    });

    testWidgets('7. Subtree Caching & Gesture Recognizer Stability: Unaffected lines retain recognizers',
        (tester) async {
      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1); // Line 1 only

      // Initial Render (unselected)
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: null),
      );
      await tester.pumpAndSettle();

      // Inspect an unaffected line (index 4, 5th line on Page 2, completely unaffected by Ayah 1)
      final lineRichTextsBefore = getLineRichTexts(tester);
      final lineSpansBefore = (lineRichTextsBefore[4].text as TextSpan).children!;
      final lineRecognizerBefore = (lineSpansBefore[0] as TextSpan).recognizer;

      // Select Ayah 1 on Line 1
      await tester.pumpWidget(
        buildPageHarness(pageNumber: 2, selectedAyahId: ayah1),
      );
      await tester.pumpAndSettle();

      final lineRichTextsAfter = getLineRichTexts(tester);
      final lineSpansAfter = (lineRichTextsAfter[4].text as TextSpan).children!;
      final lineRecognizerAfter = (lineSpansAfter[0] as TextSpan).recognizer;

      // The recognizer on unaffected line must be IDENTICAL (retained in memory without reallocation)
      expect(identical(lineRecognizerBefore, lineRecognizerAfter), isTrue,
          reason: 'Unaffected line recognizer must be retained in-place across selection changes');
    });
  });
}
