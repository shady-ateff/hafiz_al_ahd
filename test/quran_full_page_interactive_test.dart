import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_page_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeQuranRepository implements BaseQuranRepository {
  final Map<int, QuranPage> pages;
  FakeQuranRepository(this.pages);

  @override
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber) async {
    final page = pages[pageNumber];
    if (page != null) return Right(page);
    return Left(CacheFailure(message: 'Page not found'));
  }
}

class TestQuranCubit extends QuranCubit {
  final Map<int, QuranState> _testPagesCache = {};

  TestQuranCubit({
    required super.getQuranPageUseCase,
    super.mappingRepository,
  });

  @override
  Future<void> initFonts() async {
    // No-op in test: avoids downloading fonts from GitHub over network
  }

  @override
  QuranPageLoaded? getCachedPage(int pageNumber) {
    return _testPagesCache[pageNumber] as QuranPageLoaded?;
  }

  @override
  Future<void> loadPage(int pageNumber) async {
    if (_testPagesCache.containsKey(pageNumber)) {
      emit(_testPagesCache[pageNumber]!);
      return;
    }

    final failureOrPage = await getQuranPageUseCase(pageNumber);
    await failureOrPage.fold(
      (failure) async {
        emit(QuranError(failure.message));
      },
      (page) async {
        List<QuranLineMapping>? lineMappings;
        if (mappingRepository != null) {
          await mappingRepository!.init();
          final mappingResult =
              await mappingRepository!.getPageMapping(pageNumber);
          lineMappings = mappingResult.getOrElse(() => []);
        }

        final state = QuranPageLoaded(
          page: page,
          isFontLoaded: true,
          lineMappings: lineMappings,
        );
        _testPagesCache[pageNumber] = state;
        emit(state);
      },
    );
  }
}

void main() {
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
    final initResult = await repository.init();
    expect(initResult.isRight(), isTrue);

    // Load all 604 pages from quran_lines.json
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

  Widget buildTestApp({
    required Widget child,
    Size viewport = const Size(400, 800),
  }) {
    return BlocProvider<QuranSettingsCubit>(
      create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Phase 2.4 — 1. Full Page Layout & Metric Parity (0.0px Deviation)', () {
    final representativePages = [1, 2, 48, 201, 604];

    for (final pageNum in representativePages) {
      testWidgets('Page $pageNum: Layout dimensions & line counts parity',
          (tester) async {
        final page = allPages[pageNum]!;
        final mappingResult = await repository.getPageMapping(pageNum);
        final lineMappings = mappingResult.getOrElse(() => []);

        final legacyKey = GlobalKey();
        final interactiveKey = GlobalKey();

        // 1. Pump Legacy QuranPageWidget (lineMappings == null)
        await tester.pumpWidget(
          buildTestApp(
            child: RepaintBoundary(
              key: legacyKey,
              child: QuranPageWidget(
                page: page,
                isFontLoaded: true,
                lineMappings: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final legacyBox =
            legacyKey.currentContext!.findRenderObject() as RenderBox;
        final legacySize = legacyBox.size;

        // 2. Pump Interactive QuranPageWidget (lineMappings != null)
        await tester.pumpWidget(
          buildTestApp(
            child: RepaintBoundary(
              key: interactiveKey,
              child: QuranPageWidget(
                page: page,
                isFontLoaded: true,
                lineMappings: lineMappings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final interactiveBox =
            interactiveKey.currentContext!.findRenderObject() as RenderBox;
        final interactiveSize = interactiveBox.size;

        // Layout metric assertions
        expect(
          interactiveSize.width,
          moreOrLessEquals(legacySize.width, epsilon: 0.01),
          reason: 'Width mismatch on Page $pageNum',
        );
        expect(
          interactiveSize.height,
          moreOrLessEquals(legacySize.height, epsilon: 0.01),
          reason: 'Height mismatch on Page $pageNum',
        );

        // Verify all physical text lines are rendered via QuranInteractiveLineWidget
        final interactiveLinesFinder =
            find.byType(QuranInteractiveLineWidget);
        expect(
          interactiveLinesFinder,
          findsNWidgets(page.lines.length),
          reason: 'Every mapped line must render QuranInteractiveLineWidget on Page $pageNum',
        );
      });
    }
  });

  group('Phase 2.4 — 2. Visual Parity & Pixel Diff Evidence (Pages 1, 2, 48, 201, 604)', () {
    final screenshotPages = [1, 2, 48, 201, 604];

    for (final pageNum in screenshotPages) {
      testWidgets('Screenshot & Pixel Comparison for Page $pageNum',
          (tester) async {
        final page = allPages[pageNum]!;
        final mappingResult = await repository.getPageMapping(pageNum);
        final lineMappings = mappingResult.getOrElse(() => []);

        final beforeKey = GlobalKey();
        final afterKey = GlobalKey();

        // 1. Pump Legacy (Before)
        await tester.pumpWidget(
          buildTestApp(
            child: RepaintBoundary(
              key: beforeKey,
              child: QuranPageWidget(
                page: page,
                isFontLoaded: true,
                lineMappings: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Uint8List? beforePngBytes;
        Uint8List? beforeRawBytes;
        await tester.runAsync(() async {
          final boundary = beforeKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
          final rawData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (pngData != null) {
            beforePngBytes = pngData.buffer.asUint8List();
            final beforeFile =
                File('reports/screenshots/page_${pageNum}_before.png');
            await beforeFile.writeAsBytes(beforePngBytes!);
          }
          if (rawData != null) {
            beforeRawBytes = rawData.buffer.asUint8List();
          }
        });

        // 2. Pump Interactive (After)
        await tester.pumpWidget(
          buildTestApp(
            child: RepaintBoundary(
              key: afterKey,
              child: QuranPageWidget(
                page: page,
                isFontLoaded: true,
                lineMappings: lineMappings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Uint8List? afterPngBytes;
        Uint8List? afterRawBytes;
        await tester.runAsync(() async {
          final boundary = afterKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
          final rawData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (pngData != null) {
            afterPngBytes = pngData.buffer.asUint8List();
            final afterFile =
                File('reports/screenshots/page_${pageNum}_after.png');
            await afterFile.writeAsBytes(afterPngBytes!);
          }
          if (rawData != null) {
            afterRawBytes = rawData.buffer.asUint8List();
          }
        });

        expect(beforePngBytes, isNotNull);
        expect(afterPngBytes, isNotNull);

        final beforeHash = sha256.convert(beforePngBytes!).toString();
        final afterHash = sha256.convert(afterPngBytes!).toString();

        int diffPixels = 0;
        int totalPixels = 0;
        if (beforeRawBytes != null && afterRawBytes != null) {
          totalPixels = beforeRawBytes!.length ~/ 4;
          for (int i = 0; i < beforeRawBytes!.length; i += 4) {
            if (beforeRawBytes![i] != afterRawBytes![i] ||
                beforeRawBytes![i + 1] != afterRawBytes![i + 1] ||
                beforeRawBytes![i + 2] != afterRawBytes![i + 2] ||
                beforeRawBytes![i + 3] != afterRawBytes![i + 3]) {
              diffPixels++;
            }
          }
        }

        final double diffPercentage = totalPixels > 0 ? (diffPixels / totalPixels) * 100 : 0.0;
        debugPrint('Page $pageNum Evidence: Before SHA256=$beforeHash, After SHA256=$afterHash, Changed Pixels=$diffPixels/$totalPixels (${diffPercentage.toStringAsFixed(2)}%)');

        // Assert 0 differing pixels between legacy and interactive text rendering
        expect(diffPixels, equals(0),
            reason: 'Zero pixel difference expected between legacy and interactive rendering on Page $pageNum');
        expect(beforeHash, equals(afterHash),
            reason: 'PNG hashes must be byte-for-byte identical on Page $pageNum');
      });
    }
  });

  group('Phase 2.4 — 3. Real Application Hierarchy Gesture Integration', () {
    testWidgets('QuranScreen complete gesture flow: Word long-press, margin tap, header, swipe & navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<QuranWord> longPressedWords = [];

      final cubit = TestQuranCubit(
        getQuranPageUseCase: GetQuranPageUseCase(FakeQuranRepository(allPages)),
        mappingRepository: repository,
      );

      // Pre-load pages so QuranScreen has cached pages immediately without showing animated Shimmer
      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>.value(
              value: QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(
              value: cubit,
            ),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              onWordLongPressed: (w) => longPressedWords.add(w),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify that QuranScreen loaded Page 1 with interactive lines
      expect(find.byType(QuranInteractiveLineWidget), findsWidgets);

      // Find Line 2 on Page 1 (Surah 1:1)
      final line2Finder = find.byWidgetPredicate(
        (w) => w is QuranInteractiveLineWidget && w.line.lineNumber == 2,
      );
      expect(line2Finder, findsOneWidget);

      final line2RichText = tester.widget<RichText>(find.descendant(
        of: line2Finder,
        matching: find.byType(RichText),
      ));
      final rootSpan = line2RichText.text as TextSpan;
      final spans = rootSpan.children!;

      // 2. Action: Long-press a Quran word (1:1:1 "بِسْمِ")
      final word0Span = spans[0] as TextSpan;
      expect(word0Span.recognizer, isA<LongPressGestureRecognizer>());
      (word0Span.recognizer as LongPressGestureRecognizer).onLongPress!();
      await tester.pump();

      // Verify onWordLongPressed fired exactly once with correct QuranWord
      expect(longPressedWords.length, equals(1));
      expect(longPressedWords.first.uthmaniText, equals('بِسْمِ'));
      expect(longPressedWords.first.location.formatted, equals('1:1:1'));

      // 3. Action: Tap between words (whitespace separator)
      final spaceSpan = spans[1] as TextSpan;
      expect(spaceSpan.recognizer, isNull, reason: 'Whitespace span must have null recognizer');

      // 4. Action: Tap page margin (empty space at middle left) -> Fullscreen toggles
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();

      // Verify fullscreen toggled: Top header animated to -150
      final topHeaderPositioned = tester.widget<AnimatedPositioned>(
        find.byWidgetPredicate((w) => w is AnimatedPositioned && (w.top == -150 || w.top == 0)),
      );
      expect(topHeaderPositioned.top, equals(-150),
          reason: 'Tapping empty margin must toggle fullscreen to hidden');
      expect(longPressedWords.length, equals(1), reason: 'Margin tap must NOT trigger onWordLongPressed');

      // Tap margin again to restore headers
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();

      // 5. Action: Tap Surah header -> Does NOT trigger onWordLongPressed
      await tester.tapAt(const Offset(200, 30));
      await tester.pump();
      expect(longPressedWords.length, equals(1), reason: 'Header tap must NOT trigger onWordLongPressed');

      // 6. Action: Swipe horizontally (PageView navigation to Page 2)
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // 7. Action: Long-press word after navigation (Page 2)
      final page2LinesFinder = find.byWidgetPredicate(
        (w) => w is QuranInteractiveLineWidget && w.line.pageNumber == 2,
      );
      expect(page2LinesFinder, findsWidgets);

      final firstLinePage2 =
          tester.firstWidget<QuranInteractiveLineWidget>(page2LinesFinder);
      final richTextPage2 = tester.widget<RichText>(find.descendant(
        of: find.byWidget(firstLinePage2),
        matching: find.byType(RichText),
      ));
      final spanP2 = (richTextPage2.text as TextSpan).children![0] as TextSpan;
      expect(spanP2.recognizer, isA<LongPressGestureRecognizer>());
      (spanP2.recognizer as LongPressGestureRecognizer).onLongPress!();
      await tester.pump();

      // Verify word from Page 2 reported
      expect(longPressedWords.length, equals(2));
      expect(longPressedWords.last.ayahId.surahNumber, equals(2)); // Al-Baqarah

      // 8. Action: Navigate back to Page 1 (No stale recognizers)
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      final line1AgainFinder = find.byWidgetPredicate(
        (w) => w is QuranInteractiveLineWidget && w.line.pageNumber == 1 && w.line.lineNumber == 2,
      );
      expect(line1AgainFinder, findsOneWidget);
      final line1AgainRichText = tester.widget<RichText>(find.descendant(
        of: line1AgainFinder,
        matching: find.byType(RichText),
      ));
      final line1AgainSpan = (line1AgainRichText.text as TextSpan).children![0] as TextSpan;
      (line1AgainSpan.recognizer as LongPressGestureRecognizer).onLongPress!();
      await tester.pump();

      expect(longPressedWords.length, equals(3));
      expect(longPressedWords.last.location.formatted, equals('1:1:1'));
    });

    testWidgets('Lifecycle & didUpdateWidget callback update verification',
        (tester) async {
      final page = allPages[1]!;
      final mapping = (await repository.getPageMapping(1)).getOrElse(() => []);
      final line = mapping.first;

      QuranWord? receivedWord;

      final key = GlobalKey();

      // 1. Mount with Callback A (Long press)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLineWidget(
              key: key,
              line: line,
              fontFamily: 'Cairo',
              dynamicHeight: 1.5,
              textColor: Colors.black87,
              onWordLongPressed: (w) => receivedWord = w,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText));
      final rootSpan = richText.text as TextSpan;
      final word0Span = rootSpan.children![0] as TextSpan;
      expect(word0Span.recognizer, isA<LongPressGestureRecognizer>());
      (word0Span.recognizer as LongPressGestureRecognizer).onLongPress!();

      expect(receivedWord, isNotNull);
      expect(receivedWord!.location.formatted, equals('1:1:1'));

      // 2. Update to Callback B via didUpdateWidget
      QuranWord? receivedWordB;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLineWidget(
              key: key,
              line: line,
              fontFamily: 'Cairo',
              dynamicHeight: 1.5,
              textColor: Colors.black87,
              onWordLongPressed: (w) => receivedWordB = w,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      (word0Span.recognizer as LongPressGestureRecognizer).onLongPress!();
      expect(receivedWordB, isNotNull);
      expect(receivedWordB!.location.formatted, equals('1:1:1'));

      // 3. Dispose widget cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      // No exceptions or memory leaks
    });
  });
}
