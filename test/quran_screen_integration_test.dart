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
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
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

class TestIntegrationQuranCubit extends QuranCubit {
  final Map<int, QuranState> _testPagesCache = {};

  TestIntegrationQuranCubit({
    required super.getQuranPageUseCase,
    super.mappingRepository,
  });

  @override
  Future<void> initFonts() async {
    // Avoid network/disk operations in tests
  }

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
  void toggleAyahSelection(AyahId ayahId, {int? pageNumber}) {
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

    final isSameAyah = targetState.selectedAyahId == ayahId;
    final updatedState = targetState.copyWith(
      selectedAyahId: isSameAyah ? null : ayahId,
      clearSelectedAyah: isSameAyah,
    );

    _testPagesCache[targetPage] = updatedState;
    emit(updatedState);
  }

  @override
  Future<void> preloadPage(int pageNumber) async {
    if (_testPagesCache.containsKey(pageNumber)) return;
    final failureOrPage = await getQuranPageUseCase(pageNumber);
    await failureOrPage.fold(
      (failure) async {},
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
      },
    );
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
    if (_testPagesCache.containsKey(pageNumber)) {
      final cached = _testPagesCache[pageNumber]!;
      if (cached is QuranPageLoaded && cached.selectedAyahId != null) {
        final sanitized = cached.copyWith(clearSelectedAyah: true);
        _testPagesCache[pageNumber] = sanitized;
        emit(sanitized);
        return;
      }
      emit(cached);
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
  });

  Widget buildQuranScreenApp({
    required TestIntegrationQuranCubit cubit,
    Size viewport = const Size(1080, 2400),
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<QuranCubit>.value(value: cubit),
        BlocProvider<QuranSettingsCubit>(
          create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: const QuranScreen(initialPage: 1),
        ),
      ),
    );
  }

  group('Phase 2.5 — Step 4: QuranScreen Integration & Gesture Arena', () {
    late TestIntegrationQuranCubit cubit;

    setUp(() {
      final fakeRepo = FakeQuranRepository(allPages);
      final useCase = GetQuranPageUseCase(fakeRepo);
      cubit = TestIntegrationQuranCubit(
        getQuranPageUseCase: useCase,
        mappingRepository: repository,
      );
    });

    tearDown(() {
      cubit.close();
    });

    testWidgets('1. Long-press on word selects Ayah and highlights it in QuranScreen',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pre-cache pages
      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // Find first line on Page 1 (Surah Al-Fatiha, Line 2)
      final lineFinder = find.byWidgetPredicate(
        (w) => w is QuranInteractiveLineWidget && w.line.pageNumber == 1 && w.line.lineNumber == 2,
      );
      expect(lineFinder, findsOneWidget);

      final lineWidget = tester.widget<QuranInteractiveLineWidget>(lineFinder);
      final word0 = lineWidget.line.words[0];
      final ayah1 = word0.ayahId; // 1:1

      // 1. Long-press word 0
      final richTextFinder = find.descendant(of: lineFinder, matching: find.byType(RichText));
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;
      final word0Span = rootSpan.children![0] as TextSpan;

      expect(word0Span.recognizer, isA<LongPressGestureRecognizer>());
      (word0Span.recognizer as LongPressGestureRecognizer).onLongPress!();
      await tester.pumpAndSettle();

      // 2. Verify cubit state updated
      expect(cubit.state, isA<QuranPageLoaded>());
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));

      // 3. Verify widget received selectedAyahId and word is highlighted
      final updatedLineWidget = tester.widget<QuranInteractiveLineWidget>(lineFinder);
      expect(updatedLineWidget.selectedAyahId, equals(ayah1));

      final updatedRichText = tester.widget<RichText>(richTextFinder);
      final updatedRootSpan = updatedRichText.text as TextSpan;
      final updatedWord0Span = updatedRootSpan.children![0] as TextSpan;
      expect(updatedWord0Span.style?.backgroundColor, isNotNull);
    });

    testWidgets('2. Long-pressing another Ayah replaces selection, and again clears it',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final ayah2 = AyahId(surahNumber: 1, ayahNumber: 2);

      // Select Ayah 1
      cubit.toggleAyahSelection(ayah1);
      await tester.pumpAndSettle();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));

      // Select Ayah 2 -> Replaces Ayah 1
      cubit.toggleAyahSelection(ayah2);
      await tester.pumpAndSettle();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah2));

      // Select Ayah 2 again -> Toggles and clears selection
      cubit.toggleAyahSelection(ayah2);
      await tester.pumpAndSettle();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);
    });

    testWidgets('3. Single Tap on word/margin/header toggles Full Screen; Long-press does NOT toggle',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      AnimatedPositioned getTopHeader() {
        return tester.widget<AnimatedPositioned>(
          find.byWidgetPredicate(
            (w) => w is AnimatedPositioned && (w.top == -150 || w.top == 0),
          ),
        );
      }

      // Initial state: not full screen (top == 0)
      expect(getTopHeader().top, equals(0));

      // A. Single Tap on empty margin -> Full Screen toggles (-150)
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      expect(getTopHeader().top, equals(-150));

      // B. Single Tap on empty margin -> Restores normal mode (0)
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      expect(getTopHeader().top, equals(0));

      // C. Long-press on word -> Selects Ayah WITHOUT toggling Full Screen!
      final lineFinder = find.byWidgetPredicate(
        (w) => w is QuranInteractiveLineWidget && w.line.pageNumber == 1 && w.line.lineNumber == 2,
      );
      final richText = tester.widget<RichText>(
        find.descendant(of: lineFinder, matching: find.byType(RichText)),
      );
      final word0Span = (richText.text as TextSpan).children![0] as TextSpan;
      final longPressRecognizer = word0Span.recognizer as LongPressGestureRecognizer;

      longPressRecognizer.onLongPress!();
      await tester.pumpAndSettle();

      // Verify Ayah selected
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNotNull);
      // Verify Full Screen did NOT toggle (top still 0!)
      expect(getTopHeader().top, equals(0));
    });

    testWidgets('4. Page navigation via swipe clears selection and prevents stale selection',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);

      // 1. Select Ayah 1 on Page 1
      cubit.toggleAyahSelection(ayah1);
      await tester.pumpAndSettle();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));

      // 2. Swipe horizontally to Page 2
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Verify selection is cleared on page change
      expect(cubit.state, isA<QuranPageLoaded>());
      final p2State = cubit.state as QuranPageLoaded;
      expect(p2State.page.pageNumber, equals(2));
      expect(p2State.selectedAyahId, isNull,
          reason: 'Navigating to another page must clear selection');

      // 3. Swipe back to Page 1
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      // Verify returning to Page 1 has NO stale selection
      final p1ReloadedState = cubit.state as QuranPageLoaded;
      expect(p1ReloadedState.page.pageNumber, equals(1));
      expect(p1ReloadedState.selectedAyahId, isNull,
          reason: 'Reloading cached Page 1 must not restore stale selection');
    });

    testWidgets('5. Selection works correctly in both Full Screen and normal modes',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // Toggle to Full Screen
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();

      final topHeader = tester.widget<AnimatedPositioned>(
        find.byWidgetPredicate(
          (w) => w is AnimatedPositioned && (w.top == -150 || w.top == 0),
        ),
      );
      expect(topHeader.top, equals(-150)); // In Full Screen

      // Select Ayah while in Full Screen
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      cubit.toggleAyahSelection(ayah1);
      await tester.pumpAndSettle();

      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));

      // Toggle back to Normal mode
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();

      // Selection is still preserved while on the same page
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));
    });
  });
}

