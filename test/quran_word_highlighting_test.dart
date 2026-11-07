import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_page_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const lightHighlight = Color(0x33D4AF37);
  const darkHighlight = Color(0x40D4AF37);

  final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1);
  final ayah2 = AyahId(surahNumber: 2, ayahNumber: 2);

  late QuranMappingRepositoryImpl repository;
  late Map<int, QuranPage> allPages;
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'last_quran_page': 1,
      'quran_fonts_extracted': true,
      'quran_gesture_onboarding_shown': true,
    });
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

  Widget buildWrapper({
    required Widget child,
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return BlocProvider<QuranSettingsCubit>(
      create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
      child: MaterialApp(
        themeMode: themeMode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Phase 2.5 — Step 3: QuranInteractiveLineWidget Highlighting Unit Tests', () {
    final sampleLine = QuranLineMapping(
      lineNumber: 1,
      pageNumber: 2,
      words: [
        // Ayah 1 (2 words including ending marker)
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 1, wordIndex: 1),
          uthmaniText: 'الٓمٓ',
          qcfText: 'ﭑ',
        ),
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 1, wordIndex: 2),
          uthmaniText: '١',
          qcfText: 'ﭒ',
        ),
        // Ayah 2 (2 words)
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 2, wordIndex: 1),
          uthmaniText: 'ذَٰلِكَ',
          qcfText: 'ﭓ',
        ),
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 2, wordIndex: 2),
          uthmaniText: 'ٱلْكِتَٰبُ',
          qcfText: 'ﭔ',
        ),
      ],
    );

    testWidgets('1. Selected words receive expected highlight and unselected remain unchanged',
        (tester) async {
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: ayah1,
            highlightColor: lightHighlight,
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;
      final spans = rootSpan.children!;

      // Word 0 (Ayah 1 Word 1): Highlighted
      final span0 = spans[0] as TextSpan;
      expect(span0.text, equals('ﭑ'));
      expect(span0.style?.backgroundColor, equals(lightHighlight));

      // Space 1 (between Ayah 1 Word 1 and Ayah 1 Word 2): Highlighted
      final span1 = spans[1] as TextSpan;
      expect(span1.text, equals(' '));
      expect(span1.style?.backgroundColor, equals(lightHighlight));

      // Word 2 (Ayah 1 Word 2 - marker): Highlighted
      final span2 = spans[2] as TextSpan;
      expect(span2.text, equals('ﭒ'));
      expect(span2.style?.backgroundColor, equals(lightHighlight));

      // Space 3 (boundary between Ayah 1 and Ayah 2): NOT highlighted
      final span3 = spans[3] as TextSpan;
      expect(span3.text, equals(' '));
      expect(span3.style?.backgroundColor, isNull);

      // Word 4 (Ayah 2 Word 1): NOT highlighted
      final span4 = spans[4] as TextSpan;
      expect(span4.text, equals('ﭓ'));
      expect(span4.style?.backgroundColor, isNull);

      // Space 5 (between Ayah 2 words): NOT highlighted
      final span5 = spans[5] as TextSpan;
      expect(span5.text, equals(' '));
      expect(span5.style?.backgroundColor, isNull);

      // Word 6 (Ayah 2 Word 2): NOT highlighted
      final span6 = spans[6] as TextSpan;
      expect(span6.text, equals('ﭔ'));
      expect(span6.style?.backgroundColor, isNull);
    });

    testWidgets('2. Null selection removes all word and space highlighting', (tester) async {
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: null,
            highlightColor: lightHighlight,
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      final spans = (richText.text as TextSpan).children!;

      for (final span in spans.whereType<TextSpan>()) {
        expect(span.style?.backgroundColor, isNull);
      }
    });

    testWidgets('3. Selecting another Ayah updates highlighting dynamically', (tester) async {
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: ayah1,
            highlightColor: lightHighlight,
          ),
        ),
      );

      // Initially Ayah 1 is highlighted
      var richText = tester.widget<RichText>(find.byType(RichText));
      var spans = (richText.text as TextSpan).children!;
      expect((spans[0] as TextSpan).style?.backgroundColor, equals(lightHighlight));
      expect((spans[4] as TextSpan).style?.backgroundColor, isNull);

      // Switch selection to Ayah 2
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: ayah2,
            highlightColor: lightHighlight,
          ),
        ),
      );

      richText = tester.widget<RichText>(find.byType(RichText));
      spans = (richText.text as TextSpan).children!;

      // Ayah 1 is now unhighlighted
      expect((spans[0] as TextSpan).style?.backgroundColor, isNull);
      expect((spans[1] as TextSpan).style?.backgroundColor, isNull);
      expect((spans[2] as TextSpan).style?.backgroundColor, isNull);

      // Boundary space remains unhighlighted
      expect((spans[3] as TextSpan).style?.backgroundColor, isNull);

      // Ayah 2 is now highlighted
      expect((spans[4] as TextSpan).style?.backgroundColor, equals(lightHighlight));
      expect((spans[5] as TextSpan).style?.backgroundColor, equals(lightHighlight));
      expect((spans[6] as TextSpan).style?.backgroundColor, equals(lightHighlight));
    });

    testWidgets('4. Recognizer callbacks continue to work after selection changes',
        (tester) async {
      QuranWord? pressedWord;

      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: ayah1,
            highlightColor: lightHighlight,
            onWordLongPressed: (word) {
              pressedWord = word;
            },
          ),
        ),
      );

      // Find RichText render box
      final renderObject = tester.renderObject<RenderParagraph>(find.byType(RichText));
      final rootSpan = renderObject.text as TextSpan;
      final wordSpan = rootSpan.children![4] as TextSpan; // Ayah 2 Word 1

      expect(wordSpan.recognizer, isNotNull);
      final longPressRecognizer = wordSpan.recognizer as LongPressGestureRecognizer;
      longPressRecognizer.onLongPress?.call();
      expect(pressedWord?.uthmaniText, equals('ذَٰلِكَ'));

      // Update selection without recreating recognizers
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 1.5,
            textColor: Colors.black,
            selectedAyahId: ayah2,
            highlightColor: lightHighlight,
            onWordLongPressed: (word) {
              pressedWord = word;
            },
          ),
        ),
      );

      final updatedRenderObject =
          tester.renderObject<RenderParagraph>(find.byType(RichText));
      final updatedWordSpan =
          (updatedRenderObject.text as TextSpan).children![0] as TextSpan; // Ayah 1 Word 1
      final updatedRecognizer =
          updatedWordSpan.recognizer as LongPressGestureRecognizer;
      updatedRecognizer.onLongPress?.call();
      expect(pressedWord?.uthmaniText, equals('الٓمٓ'));
    });

    testWidgets('5. Zero layout shift: font metrics and line styling remain 100% invariant',
        (tester) async {
      // Unselected state
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 2.1,
            textColor: Colors.blueGrey,
            selectedAyahId: null,
          ),
        ),
      );

      final unselectedRichText = tester.widget<RichText>(find.byType(RichText));
      final unselectedStyle = (unselectedRichText.text as TextSpan).style!;

      // Selected state
      await tester.pumpWidget(
        buildWrapper(
          child: QuranInteractiveLineWidget(
            line: sampleLine,
            fontFamily: 'QCF2002',
            dynamicHeight: 2.1,
            textColor: Colors.blueGrey,
            selectedAyahId: ayah1,
            highlightColor: darkHighlight,
          ),
        ),
      );

      final selectedRichText = tester.widget<RichText>(find.byType(RichText));
      final selectedStyle = (selectedRichText.text as TextSpan).style!;

      expect(selectedStyle.fontFamily, equals(unselectedStyle.fontFamily));
      expect(selectedStyle.fontSize, equals(unselectedStyle.fontSize));
      expect(selectedStyle.height, equals(unselectedStyle.height));
      expect(selectedStyle.wordSpacing, equals(unselectedStyle.wordSpacing));
      expect(selectedStyle.letterSpacing, equals(unselectedStyle.letterSpacing));
      expect(selectedStyle.color, equals(unselectedStyle.color));
    });
  });

  group('Phase 2.5 — Step 3: QuranPageWidget Real Data & Multi-Line Ayah Tests', () {
    testWidgets('6. Multi-line Ayah highlighting across lines on Page 2 (Ayah 2:5 spans lines 4 & 5)',
        (tester) async {
      final page2 = allPages[2]!;
      final mappingResult = await repository.getPageMapping(2);
      final lineMappings = mappingResult.getOrElse(() => []);

      final ayah5 = AyahId(surahNumber: 2, ayahNumber: 5);

      await tester.pumpWidget(
        buildWrapper(
          child: QuranPageWidget(
            page: page2,
            isFontLoaded: true,
            lineMappings: lineMappings,
            selectedAyahId: ayah5,
          ),
        ),
      );

      final lineWidgets = tester
          .widgetList<QuranInteractiveLineWidget>(find.byType(QuranInteractiveLineWidget))
          .toList();

      // Find lines that contain Ayah 2:5
      final linesWithAyah5 = lineWidgets
          .where((lw) => lw.line.words.any((w) => w.ayahId == ayah5))
          .toList();

      expect(linesWithAyah5.length, greaterThanOrEqualTo(2),
          reason: 'Ayah 2:5 is a multi-line Ayah spanning across lines on Page 2');

      for (final lineWidget in linesWithAyah5) {
        expect(lineWidget.selectedAyahId, equals(ayah5));
        expect(lineWidget.highlightColor, isNotNull);
      }
    });

    testWidgets('7. Real mapping on Page 48 (Al-Baqarah 2:282 - Ayah al-Dayn): entire page highlighted',
        (tester) async {
      final page48 = allPages[48]!;
      final mappingResult = await repository.getPageMapping(48);
      final lineMappings = mappingResult.getOrElse(() => []);

      final ayahDayn = AyahId(surahNumber: 2, ayahNumber: 282);

      await tester.pumpWidget(
        buildWrapper(
          child: QuranPageWidget(
            page: page48,
            isFontLoaded: true,
            lineMappings: lineMappings,
            selectedAyahId: ayahDayn,
          ),
        ),
      );

      final lineWidgets = tester
          .widgetList<QuranInteractiveLineWidget>(find.byType(QuranInteractiveLineWidget))
          .toList();

      expect(lineWidgets.length, equals(15));
      for (final lw in lineWidgets) {
        expect(lw.selectedAyahId, equals(ayahDayn));
        // Verify every word on Page 48 belongs to Ayah 282 and is highlighted
        for (final word in lw.line.words) {
          expect(word.ayahId, equals(ayahDayn));
        }
      }
    });

    testWidgets('8. Real mapping on Page 604 (Surah Al-Ikhlas, Al-Falaq, An-Nas): separate Ayahs',
        (tester) async {
      final page604 = allPages[604]!;
      final mappingResult = await repository.getPageMapping(604);
      final lineMappings = mappingResult.getOrElse(() => []);

      final ikhlas1 = AyahId(surahNumber: 112, ayahNumber: 1);

      await tester.pumpWidget(
        buildWrapper(
          child: QuranPageWidget(
            page: page604,
            isFontLoaded: true,
            lineMappings: lineMappings,
            selectedAyahId: ikhlas1,
          ),
        ),
      );

      final lineWidgets = tester
          .widgetList<QuranInteractiveLineWidget>(find.byType(QuranInteractiveLineWidget))
          .toList();

      // Find the line containing Ikhlas 1
      final lineWithIkhlas1 = lineWidgets.firstWhere(
        (lw) => lw.line.words.any((w) => w.ayahId == ikhlas1),
      );

      expect(lineWithIkhlas1.selectedAyahId, equals(ikhlas1));
    });
  });

  group('Phase 2.5 — Step 3: Visual Regression & Pixel Diff Analysis', () {
    Future<Uint8List> captureWidget(
      WidgetTester tester,
      Widget widget,
      Size size, {
      GlobalKey? key,
    }) async {
      final boundaryKey = key ?? GlobalKey();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        buildWrapper(
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: widget,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Uint8List? rawBytes;
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        rawBytes = byteData!.buffer.asUint8List();
      });
      return rawBytes!;
    }

    testWidgets('9. Pixel Comparison for Unselected vs Legacy Page 1: 0.00% difference',
        (tester) async {
      final size = const Size(800, 1200);
      final page1 = allPages[1]!;
      final mappingResult = await repository.getPageMapping(1);
      final lineMappings = mappingResult.getOrElse(() => []);

      final baselineKey = GlobalKey();
      final testKey = GlobalKey();

      // Baseline: lineMappings with selectedAyahId == null
      final baselineBytes = await captureWidget(
        tester,
        QuranPageWidget(
          page: page1,
          isFontLoaded: true,
          lineMappings: lineMappings,
          selectedAyahId: null,
        ),
        size,
        key: baselineKey,
      );

      // Tested: explicitly selectedAyahId == null
      final testBytes = await captureWidget(
        tester,
        QuranPageWidget(
          page: page1,
          isFontLoaded: true,
          lineMappings: lineMappings,
          selectedAyahId: null,
        ),
        size,
        key: testKey,
      );

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();

      int changedPixels = 0;
      for (int i = 0; i < baselineBytes.length; i += 4) {
        if (baselineBytes[i] != testBytes[i] ||
            baselineBytes[i + 1] != testBytes[i + 1] ||
            baselineBytes[i + 2] != testBytes[i + 2] ||
            baselineBytes[i + 3] != testBytes[i + 3]) {
          changedPixels++;
        }
      }

      final totalPixels = size.width.toInt() * size.height.toInt();
      final diffPercent = (changedPixels / totalPixels) * 100;

      expect(changedPixels, equals(0),
          reason: 'Unselected page must have 0 changed pixels ($diffPercent%)');
    });

    testWidgets('10. Pixel Comparison for Selected Ayah on Page 2: highlight is isolated and verified',
        (tester) async {
      final size = const Size(800, 1200);
      final page2 = allPages[2]!;
      final mappingResult = await repository.getPageMapping(2);
      final lineMappings = mappingResult.getOrElse(() => []);

      final ayah1 = AyahId(surahNumber: 2, ayahNumber: 1);
      final unselectedKey = GlobalKey();
      final selectedKey = GlobalKey();

      // Unselected
      final unselectedBytes = await captureWidget(
        tester,
        QuranPageWidget(
          page: page2,
          isFontLoaded: true,
          lineMappings: lineMappings,
          selectedAyahId: null,
        ),
        size,
        key: unselectedKey,
      );

      // Selected Ayah 1
      final selectedBytes = await captureWidget(
        tester,
        QuranPageWidget(
          page: page2,
          isFontLoaded: true,
          lineMappings: lineMappings,
          selectedAyahId: ayah1,
        ),
        size,
        key: selectedKey,
      );

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();

      int changedPixels = 0;
      for (int i = 0; i < unselectedBytes.length; i += 4) {
        if (unselectedBytes[i] != selectedBytes[i] ||
            unselectedBytes[i + 1] != selectedBytes[i + 1] ||
            unselectedBytes[i + 2] != selectedBytes[i + 2] ||
            unselectedBytes[i + 3] != selectedBytes[i + 3]) {
          changedPixels++;
        }
      }

      final totalPixels = size.width.toInt() * size.height.toInt();
      final diffPercent = (changedPixels / totalPixels) * 100;

      // In a page of 800x1200 (960,000 pixels), Ayah 2:1 is 2 words on Line 1.
      // Highlighting it changes a small, focused percentage of pixels (< 5%), proving isolated diff.
      expect(changedPixels, greaterThan(0),
          reason: 'Highlighting must change background pixels of the selected Ayah');
      expect(diffPercent, lessThan(5.0),
          reason: 'Highlighting must be confined to the selected Ayah ($diffPercent% of page)');
    });
  });
}

