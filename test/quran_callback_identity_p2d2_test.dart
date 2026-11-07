import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
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

class TestCallbackQuranCubit extends QuranCubit {
  final Map<int, QuranState> _testPagesCache = {};

  TestCallbackQuranCubit({
    required super.getQuranPageUseCase,
    super.mappingRepository,
  });

  @override
  Future<void> initFonts() async {}

  @override
  QuranPageLoaded? getCachedPage(int pageNumber) {
    return _testPagesCache[pageNumber] as QuranPageLoaded?;
  }

  @override
  void selectAyah(AyahId ayahId, {int? pageNumber}) {
    final targetPage = pageNumber ??
        (state is QuranPageLoaded
            ? (state as QuranPageLoaded).page.pageNumber
            : 1);
    final targetState = getCachedPage(targetPage) ??
        (state is QuranPageLoaded &&
                (state as QuranPageLoaded).page.pageNumber == targetPage
            ? state as QuranPageLoaded
            : null);
    if (targetState == null) return;

    if (targetState.selectedAyahId == ayahId) return;

    final updatedState = targetState.copyWith(
      selectedAyahId: ayahId,
      clearSelectedAyah: false,
    );

    _testPagesCache[targetPage] = updatedState;
    emit(updatedState);
  }

  @override
  void clearSelection() {
    final currentState = state;
    if (currentState is! QuranPageLoaded) return;
    if (currentState.selectedAyahId == null) return;

    final updatedState = currentState.copyWith(clearSelectedAyah: true);
    _testPagesCache[currentState.page.pageNumber] = updatedState;
    emit(updatedState);
  }

  @override
  Future<void> loadPage(int pageNumber) async {
    final cached = _testPagesCache[pageNumber];
    if (cached != null) {
      emit(cached);
      return;
    }
    final failureOrPage = await getQuranPageUseCase(pageNumber);
    await failureOrPage.fold(
      (failure) async {},
      (page) async {
        List<QuranLineMapping>? lineMappings;
        if (mappingRepository != null) {
          final mappingResult = await mappingRepository!.getPageMapping(pageNumber);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranMappingRepositoryImpl repository;
  late Map<int, QuranPage> allPages;
  late SharedPreferences prefs;
  late GetQuranPageUseCase getQuranPageUseCase;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'last_quran_page': 2,
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

    if (!sl.isRegistered<BaseQuranMappingRepository>()) {
      sl.registerSingleton<BaseQuranMappingRepository>(repository);
    }

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

    final fakeRepo = FakeQuranRepository(allPages);
    getQuranPageUseCase = GetQuranPageUseCase(fakeRepo);
  });

  Widget buildQuranScreenHarness({
    required TestCallbackQuranCubit cubit,
    int initialPage = 2,
    ValueChanged<QuranWord>? onWordTapped,
    ValueChanged<QuranWord>? onWordLongPressed,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<QuranCubit>.value(value: cubit),
        BlocProvider<QuranSettingsCubit>(
          create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
        ),
      ],
      child: MaterialApp(
        home: QuranScreen(
          initialPage: initialPage,
          onWordTapped: onWordTapped,
          onWordLongPressed: onWordLongPressed,
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

  group('Phase P2-D.2: Callback Identity and Recognizer Lifecycle Tests', () {
    testWidgets(
      '1. Verify callback identities are preserved across QuranScreen rebuilds',
      (tester) async {
        final cubit = TestCallbackQuranCubit(
          getQuranPageUseCase: getQuranPageUseCase,
          mappingRepository: repository,
        );
        await cubit.loadPage(2);

        await tester.pumpWidget(buildQuranScreenHarness(cubit: cubit, initialPage: 2));
        await tester.pumpAndSettle();

        // Capture initial callbacks
        final pageWidgetBefore = tester.widget<QuranPageWidget>(find.byType(QuranPageWidget));
        final onTappedBefore = pageWidgetBefore.onWordTapped;
        final onLongPressedBefore = pageWidgetBefore.onWordLongPressed;

        expect(onTappedBefore, isNotNull);
        expect(onLongPressedBefore, isNotNull);

        final linesBefore = tester.widgetList<QuranInteractiveLineWidget>(
          find.byType(QuranInteractiveLineWidget),
        ).toList();
        expect(linesBefore.isNotEmpty, isTrue);
        final lineBefore = linesBefore.first;
        final lineTappedBefore = lineBefore.onWordTapped;
        final lineLongPressedBefore = lineBefore.onWordLongPressed;

        // Trigger Ayah selection on Line 1
        final ayah2_1 = AyahId(surahNumber: 2, ayahNumber: 1);
        cubit.selectAyah(ayah2_1, pageNumber: 2);
        await tester.pump();
        await tester.pumpAndSettle();

        // Capture after rebuild
        final pageWidgetAfter = tester.widget<QuranPageWidget>(find.byType(QuranPageWidget));
        final onTappedAfter = pageWidgetAfter.onWordTapped;
        final onLongPressedAfter = pageWidgetAfter.onWordLongPressed;

        final linesAfter = tester.widgetList<QuranInteractiveLineWidget>(
          find.byType(QuranInteractiveLineWidget),
        ).toList();
        final lineAfter = linesAfter.first;
        final lineTappedAfter = lineAfter.onWordTapped;
        final lineLongPressedAfter = lineAfter.onWordLongPressed;

        // PHYSICAL PROOF: Callbacks must be identical
        expect(identical(onTappedBefore, onTappedAfter), isTrue,
            reason: 'QuranPageWidget onWordTapped must be identical across rebuilds');
        expect(identical(onLongPressedBefore, onLongPressedAfter), isTrue,
            reason: 'QuranPageWidget onWordLongPressed must be identical across rebuilds');
        expect(identical(lineTappedBefore, lineTappedAfter), isTrue,
            reason: 'QuranInteractiveLineWidget onWordTapped must be identical across rebuilds');
        expect(identical(lineLongPressedBefore, lineLongPressedAfter), isTrue,
            reason: 'QuranInteractiveLineWidget onWordLongPressed must be identical across rebuilds');
      },
    );

    testWidgets(
      '2. Subtree Recognizer Stability: Unaffected lines retain existing gesture recognizers in-place',
      (tester) async {
        final cubit = TestCallbackQuranCubit(
          getQuranPageUseCase: getQuranPageUseCase,
          mappingRepository: repository,
        );
        await cubit.loadPage(2);

        await tester.pumpWidget(buildQuranScreenHarness(cubit: cubit, initialPage: 2));
        await tester.pumpAndSettle();

        // Page 2 has 5 interactive lines:
        // Line indices correspond to line mappings. Last interactive line is Line 7 (index 4 in rich texts).
        final lineRichTextsBefore = getLineRichTexts(tester);
        expect(lineRichTextsBefore.length, greaterThanOrEqualTo(5));

        // Let's inspect the last line on Page 2 (completely unaffected by Ayah 2:1 on Line 3)
        final lastLineIndex = lineRichTextsBefore.length - 1;
        final spansBefore = (lineRichTextsBefore[lastLineIndex].text as TextSpan).children!;
        final recognizerBefore = (spansBefore[0] as TextSpan).recognizer;
        expect(recognizerBefore, isA<LongPressGestureRecognizer>());

        // Select Ayah 2:1 (on Line 3)
        final ayah2_1 = AyahId(surahNumber: 2, ayahNumber: 1);
        cubit.selectAyah(ayah2_1, pageNumber: 2);
        await tester.pump();
        await tester.pumpAndSettle();

        final lineRichTextsAfter = getLineRichTexts(tester);
        final spansAfter = (lineRichTextsAfter[lastLineIndex].text as TextSpan).children!;
        final recognizerAfter = (spansAfter[0] as TextSpan).recognizer;

        // PHYSICAL PROOF: Unaffected line recognizer must be identical in memory
        expect(identical(recognizerBefore, recognizerAfter), isTrue,
            reason: 'Unaffected line recognizer was retained in-place without recreation');
      },
    );

    testWidgets(
      '3. PageNumber isolation: Callbacks capture correct pageNumber and preserve gesture routing',
      (tester) async {
        final cubit = TestCallbackQuranCubit(
          getQuranPageUseCase: getQuranPageUseCase,
          mappingRepository: repository,
        );
        await cubit.loadPage(2);

        await tester.pumpWidget(buildQuranScreenHarness(cubit: cubit, initialPage: 2));
        await tester.pumpAndSettle();

        // Find word recognizer on Page 2
        final lineRichTexts = getLineRichTexts(tester);
        final spans = (lineRichTexts[0].text as TextSpan).children!;
        final wordSpan = spans[0] as TextSpan;
        final recognizer = wordSpan.recognizer;

        expect(recognizer, isA<LongPressGestureRecognizer>());
        final lpRecognizer = recognizer as LongPressGestureRecognizer;

        // Fire long press
        lpRecognizer.onLongPress?.call();
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify Ayah 2:1 was selected on Page 2
        expect(cubit.selectedAyahId, equals(AyahId(surahNumber: 2, ayahNumber: 1)));
      },
    );

    testWidgets(
      '4. External callback injection and didUpdateWidget cache invalidation',
      (tester) async {
        final cubit = TestCallbackQuranCubit(
          getQuranPageUseCase: getQuranPageUseCase,
          mappingRepository: repository,
        );
        await cubit.loadPage(2);

        int tap1Calls = 0;
        void customTap1(QuranWord w) {
          tap1Calls++;
        }

        // Pump with external callback
        await tester.pumpWidget(
          buildQuranScreenHarness(
            cubit: cubit,
            initialPage: 2,
            onWordTapped: customTap1,
          ),
        );
        await tester.pumpAndSettle();

        final pageWidget1 = tester.widget<QuranPageWidget>(find.byType(QuranPageWidget));
        expect(pageWidget1.onWordTapped, equals(customTap1));

        // Now pump with a new external callback
        int tap2Calls = 0;
        void customTap2(QuranWord w) {
          tap2Calls++;
        }

        await tester.pumpWidget(
          buildQuranScreenHarness(
            cubit: cubit,
            initialPage: 2,
            onWordTapped: customTap2,
          ),
        );
        await tester.pumpAndSettle();

        final pageWidget2 = tester.widget<QuranPageWidget>(find.byType(QuranPageWidget));
        expect(pageWidget2.onWordTapped, equals(customTap2));
        expect(identical(pageWidget1.onWordTapped, pageWidget2.onWordTapped), isFalse);
        expect(tap1Calls, equals(0));
        expect(tap2Calls, equals(0));
      },
    );
  });
}
