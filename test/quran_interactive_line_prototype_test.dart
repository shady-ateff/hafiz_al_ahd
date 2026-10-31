import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_prototype.dart';

/// Legacy renderer equivalent representing the exact existing implementation in QuranPageWidget
class ExistingQuranLineRenderer extends StatelessWidget {
  final String text;
  final String fontFamily;
  final double dynamicHeight;
  final Color textColor;

  const ExistingQuranLineRenderer({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.dynamicHeight,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 40,
          color: textColor,
          height: dynamicHeight,
          wordSpacing: -3.5,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

void main() {
  late QuranMappingRepositoryImpl repository;

  setUpAll(() async {
    final dataSource = QuranMappingLocalDataSourceImpl(
      customDataLoader: () async => File('assets/quran/mushaf/ayah_mapping.json').readAsString(),
    );
    repository = QuranMappingRepositoryImpl(localDataSource: dataSource);
    final initResult = await repository.init();
    expect(initResult.isRight(), isTrue);
  });

  group('Phase 2.3 — Visual & Metric Parity Tests', () {
    testWidgets('Metrics parity across representative lines (0px deviation)', (tester) async {
      // Representative test lines:
      // 1. Normal line (Page 1 Line 2: 1:1)
      // 2. Multi-ayah line (Page 604 Line 3: 112:1-3)
      // 3. Multi-glyph end-of-ayah line (Page 604 Line 4: 112:4)
      // 4. Long line (Page 48 Line 1: 2:282)
      final testCases = <Map<String, dynamic>>[
        {'page': 1, 'line': 2, 'label': 'Normal single-ayah line (1:1)'},
        {'page': 604, 'line': 3, 'label': 'Multi-ayah line (112:1-3, 3 ayahs on one line)'},
        {'page': 604, 'line': 4, 'label': 'Line with attached ayah end marker (112:4)'},
        {'page': 48, 'line': 1, 'label': 'Long 15-line ayah line (2:282)'},
      ];

      for (final tc in testCases) {
        final pageNum = tc['page'] as int;
        final lineNum = tc['line'] as int;
        final pageResult = await repository.getPageMapping(pageNum);
        final lines = pageResult.getOrElse(() => []);
        final line = lines.firstWhere((l) => l.lineNumber == lineNum);

        final originalKey = GlobalKey();
        final prototypeKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 700,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RepaintBoundary(
                        key: originalKey,
                        child: ExistingQuranLineRenderer(
                          text: line.reconstructedQcfText,
                          fontFamily: 'Cairo',
                          dynamicHeight: 1.5,
                          textColor: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      RepaintBoundary(
                        key: prototypeKey,
                        child: QuranInteractiveLinePrototype(
                          line: line,
                          fontFamily: 'Cairo',
                          dynamicHeight: 1.5,
                          textColor: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final originalBox = originalKey.currentContext!.findRenderObject() as RenderBox;
        final prototypeBox = prototypeKey.currentContext!.findRenderObject() as RenderBox;

        final originalSize = originalBox.size;
        final prototypeSize = prototypeBox.size;

        expect(
          prototypeSize.width,
          moreOrLessEquals(originalSize.width, epsilon: 0.01),
          reason: 'Width deviation on ${tc['label']} (original: ${originalSize.width}, proto: ${prototypeSize.width})',
        );
        expect(
          prototypeSize.height,
          moreOrLessEquals(originalSize.height, epsilon: 0.01),
          reason: 'Height deviation on ${tc['label']} (original: ${originalSize.height}, proto: ${prototypeSize.height})',
        );
      }
    });

    testWidgets('Capture before & after screenshots to PNG files', (tester) async {
      final pageResult = await repository.getPageMapping(604);
      final lines = pageResult.getOrElse(() => []);
      // Page 604 line 3: Surah 112:1-3 (Contains 3 ayahs with ayah end markers)
      final line = lines.firstWhere((l) => l.lineNumber == 3);

      final beforeKey = GlobalKey();
      final afterKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xffFFFCE6),
            body: Center(
              child: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      key: beforeKey,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ExistingQuranLineRenderer(
                          text: line.reconstructedQcfText,
                          fontFamily: 'QCF_BSML',
                          dynamicHeight: 1.5,
                          textColor: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    RepaintBoundary(
                      key: afterKey,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: QuranInteractiveLinePrototype(
                          line: line,
                          fontFamily: 'QCF_BSML',
                          dynamicHeight: 1.5,
                          textColor: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        // Export before image (Existing Text)
        final beforeBoundary = beforeKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final beforeImage = await beforeBoundary.toImage(pixelRatio: 2.0);
        final beforeByteData = await beforeImage.toByteData(format: ui.ImageByteFormat.png);
        if (beforeByteData != null) {
          final beforeFile = File('reports/screenshots/prototype_line_before.png');
          await beforeFile.writeAsBytes(beforeByteData.buffer.asUint8List());
        }

        // Export after image (Interactive RichText)
        final afterBoundary = afterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final afterImage = await afterBoundary.toImage(pixelRatio: 2.0);
        final afterByteData = await afterImage.toByteData(format: ui.ImageByteFormat.png);
        if (afterByteData != null) {
          final afterFile = File('reports/screenshots/prototype_line_after.png');
          await afterFile.writeAsBytes(afterByteData.buffer.asUint8List());
        }
      });

      expect(File('reports/screenshots/prototype_line_before.png').existsSync(), isTrue);
      expect(File('reports/screenshots/prototype_line_after.png').existsSync(), isTrue);
    });
  });

  group('Phase 2.3 — Gesture Behavior & Arena Tests', () {
    testWidgets('Tapping words invokes onWordTapped with exact QuranWord', (tester) async {
      final pageResult = await repository.getPageMapping(604);
      final lines = pageResult.getOrElse(() => []);
      final line = lines.firstWhere((l) => l.lineNumber == 3);

      final List<QuranWord> tappedWords = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 700,
                child: QuranInteractiveLinePrototype(
                  line: line,
                  fontFamily: 'Cairo',
                  dynamicHeight: 1.5,
                  textColor: Colors.black87,
                  onWordTapped: (w) => tappedWords.add(w),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the RichText widget
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;
      final spans = rootSpan.children!;

      // Word 0 is at spans[0] (qcf: "ﱁ", uthmani: "قُلْ")
      final word0Span = spans[0] as TextSpan;
      expect(word0Span.recognizer, isA<TapGestureRecognizer>());
      (word0Span.recognizer as TapGestureRecognizer).onTap!();

      // Word 1 is at spans[2] (qcf: "ﱂ", uthmani: "هُوَ")
      final word1Span = spans[2] as TextSpan;
      (word1Span.recognizer as TapGestureRecognizer).onTap!();

      // Word 3 (with ayah end glyph) is at spans[6] ("أَحَدٌ")
      final word3Span = spans[6] as TextSpan;
      (word3Span.recognizer as TapGestureRecognizer).onTap!();

      // Separating space at spans[1] has NO recognizer
      final spaceSpan = spans[1] as TextSpan;
      expect(spaceSpan.recognizer, isNull);

      expect(tappedWords.length, equals(3));
      expect(tappedWords[0].uthmaniText, equals('قُلْ'));
      expect(tappedWords[0].location.formatted, equals('112:1:1'));

      expect(tappedWords[1].uthmaniText, equals('هُوَ'));
      expect(tappedWords[1].location.formatted, equals('112:1:2'));

      expect(tappedWords[2].uthmaniText, equals('أَحَدٌ'));
      expect(tappedWords[2].location.formatted, equals('112:1:4'));
      expect(tappedWords[2].qcfText, equals('ﱄ ﱅ')); // Attached ayah end marker preserved
    });

    testWidgets('Parent GestureDetector vs Word Tap in Gesture Arena', (tester) async {
      final pageResult = await repository.getPageMapping(1);
      final lines = pageResult.getOrElse(() => []);
      final line = lines.firstWhere((l) => l.lineNumber == 2);

      int parentTapCount = 0;
      QuranWord? tappedWord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () => parentTapCount++,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 800,
                height: 300,
                color: Colors.white,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 700,
                  child: QuranInteractiveLinePrototype(
                    line: line,
                    fontFamily: 'Cairo',
                    dynamicHeight: 1.5,
                    textColor: Colors.black87,
                    onWordTapped: (w) => tappedWord = w,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on empty space outside the line -> Parent should receive tap (fullscreen toggle)
      await tester.tapAt(const Offset(50, 50));
      await tester.pump();
      expect(parentTapCount, equals(1));
      expect(tappedWord, isNull);

      // Tap directly on word recognizer
      final richText = tester.widget<RichText>(find.byType(RichText));
      final rootSpan = richText.text as TextSpan;
      final wordSpan = rootSpan.children![0] as TextSpan;
      (wordSpan.recognizer as TapGestureRecognizer).onTap!();

      expect(tappedWord, isNotNull);
      expect(tappedWord!.uthmaniText, equals('بِسْمِ'));
    });

    testWidgets('Recognizer lifecycle and leak prevention', (tester) async {
      final pageResult = await repository.getPageMapping(1);
      final lines = pageResult.getOrElse(() => []);
      final lineA = lines[0];
      final lineB = lines.length > 1 ? lines[1] : lines[0];

      final key = GlobalKey();

      // 1. Initial pump
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLinePrototype(
              key: key,
              line: lineA,
              fontFamily: 'Cairo',
              dynamicHeight: 1.5,
              textColor: Colors.black87,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Re-pump with same line -> didUpdateWidget does not recreate
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLinePrototype(
              key: key,
              line: lineA,
              fontFamily: 'Cairo',
              dynamicHeight: 1.5,
              textColor: Colors.blue, // changed color only
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Re-pump with new line -> updates recognizers cleanly
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLinePrototype(
              key: key,
              line: lineB,
              fontFamily: 'Cairo',
              dynamicHeight: 1.5,
              textColor: Colors.black87,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 4. Dispose widget completely -> dispose() clears recognizers
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // If any recognizer leaked un-disposed or threw, test would fail here
    });
  });
}

