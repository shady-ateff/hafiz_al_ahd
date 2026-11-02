import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_tafseer.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_tafseer_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_tafseer_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_ayah_action_bottom_sheet.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_tafseer_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockQuranMappingRepo implements BaseQuranMappingRepository {
  final Map<AyahId, QuranAyah> ayahs = {};
  final Map<int, List<QuranLineMapping>> pageMappings = {};

  @override
  Future<Either<Failure, void>> init() async => const Right(null);

  @override
  Future<Either<Failure, QuranAyah>> getAyah(AyahId ayahId) async {
    final ayah = ayahs[ayahId];
    if (ayah != null) return Right(ayah);
    return Left(CacheFailure(message: 'Ayah not found: $ayahId'));
  }

  @override
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(
          AyahId ayahId) async =>
      const Right([]);

  @override
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(
      int pageNumber) async {
    return Right(pageMappings[pageNumber] ?? []);
  }

  @override
  Future<Either<Failure, QuranWord>> getWord(WordLocation location) async =>
      Left(CacheFailure(message: 'Not implemented'));
}

class MockQuranRepository implements BaseQuranRepository {
  final Map<int, QuranPage> pages;
  MockQuranRepository(this.pages);

  @override
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber) async {
    final page = pages[pageNumber];
    if (page != null) return Right(page);
    return Left(ServerFailure(message: 'Page not found'));
  }
}

class FakeQuranTafseerRepository implements QuranTafseerRepository {
  final Map<AyahId, QuranTafseer> tafseerMap = {};
  bool failNext = false;
  int getTafseerCallCount = 0;

  @override
  Future<Either<Failure, QuranTafseer>> getTafseer(AyahId ayahId) async {
    getTafseerCallCount++;
    if (failNext) {
      return Left(CacheFailure(message: 'Tafseer load failed'));
    }
    final tafseer = tafseerMap[ayahId];
    if (tafseer != null) {
      return Right(tafseer);
    }
    return Right(
      QuranTafseer(
        ayahId: ayahId,
        sourceName: 'التفسير الميسر',
        rawText: 'تفسير افتراضي للآية ${ayahId.ayahNumber}',
        segments: [
          TafseerSegment(
            text: 'تفسير افتراضي للآية ${ayahId.ayahNumber}',
            type: TafseerSegmentType.commentary,
          ),
        ],
      ),
    );
  }
}

class TestQuranCubit extends QuranCubit {
  final Map<int, QuranState> _testPagesCache = {};

  TestQuranCubit({
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late MockQuranMappingRepo mockMappingRepo;
  late FakeQuranTafseerRepository fakeTafseerRepo;
  late GetQuranPageUseCase mockPageUseCase;
  late QuranAyah testAyah1;
  late QuranAyah testAyah2;

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

    testAyah1 = QuranAyah(
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

    testAyah2 = QuranAyah(
      id: AyahId(surahNumber: 1, ayahNumber: 2),
      pageNumber: 1,
      endPageNumber: 1,
      uthmaniText: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 1, ayahNumber: 2),
          pageNumber: 1,
          lineNumber: 3,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'ﱆ ﱇ ﱈ ﱉ ﱊ',
        ),
      ],
    );

    mockMappingRepo = MockQuranMappingRepo();
    mockMappingRepo.ayahs[testAyah1.id] = testAyah1;
    mockMappingRepo.ayahs[testAyah2.id] = testAyah2;

    final word1 = QuranWord(
      location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
      uthmaniText: 'بِسْمِ',
      qcfText: 'ﱁ',
    );
    final word2 = QuranWord(
      location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 2),
      uthmaniText: 'ٱللَّهِ',
      qcfText: 'ﱂ',
    );
    final word3 = QuranWord(
      location: WordLocation(surahNumber: 1, ayahNumber: 2, wordIndex: 1),
      uthmaniText: 'ٱلْحَمْدُ',
      qcfText: 'ﱆ',
    );

    final line1 = QuranLineMapping(
      lineNumber: 1,
      pageNumber: 1,
      words: [word1, word2, word3],
    );

    mockMappingRepo.pageMappings[1] = [line1];

    if (sl.isRegistered<BaseQuranMappingRepository>()) {
      sl.unregister<BaseQuranMappingRepository>();
    }
    sl.registerSingleton<BaseQuranMappingRepository>(mockMappingRepo);

    mockPageUseCase = GetQuranPageUseCase(
      MockQuranRepository({
        1: QuranPage(
          pageNumber: 1,
          lines: const [
            QuranLine(lineNumber: 1, surahNumber: 1, text: 'ﱁ ﱂ ﱆ'),
          ],
        ),
        2: QuranPage(
          pageNumber: 2,
          lines: const [
            QuranLine(lineNumber: 1, surahNumber: 2, text: 'ﭑ ﭒ'),
          ],
        ),
      }),
    );
  });

  setUp(() {
    fakeTafseerRepo = FakeQuranTafseerRepository();
    fakeTafseerRepo.tafseerMap[testAyah1.id] = QuranTafseer(
      ayahId: testAyah1.id,
      sourceName: 'التفسير الميسر',
      rawText: 'أبدأ قراءة القرآن باسم الله مستعينا به',
      segments: const [
        TafseerSegment(
          text: 'أبدأ قراءة القرآن باسم الله مستعينا به',
          type: TafseerSegmentType.commentary,
        ),
      ],
    );

    fakeTafseerRepo.tafseerMap[testAyah2.id] = QuranTafseer(
      ayahId: testAyah2.id,
      sourceName: 'التفسير الميسر',
      rawText: 'الثناء الكامل لله وحده، وهو مالك الخلق أجمعين',
      segments: const [
        TafseerSegment(
          text: 'الثناء الكامل لله وحده، وهو مالك الخلق أجمعين',
          type: TafseerSegmentType.commentary,
        ),
      ],
    );

    if (sl.isRegistered<QuranTafseerRepository>()) {
      sl.unregister<QuranTafseerRepository>();
    }
    sl.registerSingleton<QuranTafseerRepository>(fakeTafseerRepo);

    if (sl.isRegistered<GetQuranTafseerUseCase>()) {
      sl.unregister<GetQuranTafseerUseCase>();
    }
    sl.registerSingleton<GetQuranTafseerUseCase>(
      GetQuranTafseerUseCase(fakeTafseerRepo),
    );

    if (sl.isRegistered<QuranTafseerCubit>()) {
      sl.unregister<QuranTafseerCubit>();
    }
    sl.registerFactory<QuranTafseerCubit>(
      () => QuranTafseerCubit(
          getQuranTafseerUseCase: sl<GetQuranTafseerUseCase>()),
    );
  });

  Widget buildQuranScreenApp({required TestQuranCubit cubit}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<QuranSettingsCubit>(
          create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
        ),
        BlocProvider<QuranCubit>.value(value: cubit),
      ],
      child: const MaterialApp(
        home: QuranScreen(initialPage: 1),
      ),
    );
  }

  group('Phase 4B — QuranScreen & Tafseer Integration Tests', () {
    testWidgets(
        '1. Long-press Ayah -> Action Sheet -> Tap Tafseer -> Opens QuranTafseerBottomSheet with data',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cubit = TestQuranCubit(
        getQuranPageUseCase: mockPageUseCase,
        mappingRepository: mockMappingRepo,
      );

      await cubit.loadPage(1);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // Verify initial state
      expect(cubit.selectedAyahId, isNull);
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);
      expect(find.byType(QuranTafseerBottomSheet), findsNothing);

      // 1. Long-press on first line to select Ayah 1:1
      final lineWidgetFinder = find.byType(QuranInteractiveLineWidget);
      expect(lineWidgetFinder, findsWidgets);

      await tester.longPress(lineWidgetFinder.first);
      await tester.pumpAndSettle();

      // Action sheet is displayed and Ayah 1:1 is selected
      expect(cubit.selectedAyahId, equals(testAyah1.id));
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // Find the 'التفسير' button
      final tafseerBtnFinder = find.widgetWithText(InkWell, 'التفسير');
      expect(tafseerBtnFinder, findsOneWidget);

      // 2. Tap 'التفسير'
      await tester.tap(tafseerBtnFinder);
      await tester.pumpAndSettle();

      // Action sheet is dismissed, Tafseer bottom sheet is open
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);
      expect(find.byType(QuranTafseerBottomSheet), findsOneWidget);

      // Verify Ayah selection in cubit is preserved
      expect(cubit.selectedAyahId, equals(testAyah1.id),
          reason: 'Ayah selection must remain active when Tafseer is opened');

      // Verify Tafseer data is loaded and displayed
      expect(find.text('التفسير الميسر'), findsOneWidget);
      final commentaryFinder = find.byKey(const Key('tafseer_commentary_text'));
      expect(commentaryFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(commentaryFinder);
      expect((textWidget.textSpan! as TextSpan).toPlainText(),
          contains('أبدأ قراءة القرآن'));

      cubit.close();
    });

    testWidgets(
        '2. Dismissing QuranTafseerBottomSheet preserves Ayah selection on Quran page',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cubit = TestQuranCubit(
        getQuranPageUseCase: mockPageUseCase,
        mappingRepository: mockMappingRepo,
      );

      await cubit.loadPage(1);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // Long-press to open action sheet
      final lineWidgetFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineWidgetFinder.first);
      await tester.pumpAndSettle();

      // Open Tafseer sheet
      final tafseerBtnFinder = find.widgetWithText(InkWell, 'التفسير');
      await tester.tap(tafseerBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(QuranTafseerBottomSheet), findsOneWidget);
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // Dismiss Tafseer sheet via close button
      final closeButtonFinder = find.descendant(
        of: find.byType(QuranTafseerBottomSheet),
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(closeButtonFinder, findsOneWidget);

      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      // Tafseer sheet is closed
      expect(find.byType(QuranTafseerBottomSheet), findsNothing);

      // Crucial test assertion: Selection remains on the Ayah!
      expect(cubit.selectedAyahId, equals(testAyah1.id),
          reason:
              'Ayah selection must be preserved after closing Tafseer BottomSheet');

      cubit.close();
    });

    testWidgets(
        '3. Re-tapping selected Ayah after Tafseer sheet dismissal reopens action sheet and allows re-entering Tafseer',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cubit = TestQuranCubit(
        getQuranPageUseCase: mockPageUseCase,
        mappingRepository: mockMappingRepo,
      );

      await cubit.loadPage(1);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // 1. Long-press & open Tafseer
      final lineWidgetFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineWidgetFinder.first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, 'التفسير'));
      await tester.pumpAndSettle();

      // 2. Dismiss Tafseer
      final closeButtonFinder = find.descendant(
        of: find.byType(QuranTafseerBottomSheet),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(QuranTafseerBottomSheet), findsNothing);
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // 3. Single-tap on the selected Ayah
      await tester.tap(lineWidgetFinder.first);
      await tester.pumpAndSettle();

      // Action sheet reopens!
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // 4. Re-open Tafseer
      await tester.tap(find.widgetWithText(InkWell, 'التفسير'));
      await tester.pumpAndSettle();

      expect(find.byType(QuranTafseerBottomSheet), findsOneWidget);
      final commentaryFinder = find.byKey(const Key('tafseer_commentary_text'));
      expect(commentaryFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(commentaryFinder);
      expect((textWidget.textSpan! as TextSpan).toPlainText(),
          contains('أبدأ قراءة القرآن'));

      cubit.close();
    });

    testWidgets(
        '4. Error in Tafseer displays retry button and recovers cleanly without losing selection',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Simulate failure on initial load
      fakeTafseerRepo.failNext = true;

      final cubit = TestQuranCubit(
        getQuranPageUseCase: mockPageUseCase,
        mappingRepository: mockMappingRepo,
      );

      await cubit.loadPage(1);

      await tester.pumpWidget(buildQuranScreenApp(cubit: cubit));
      await tester.pumpAndSettle();

      // Open Tafseer
      final lineWidgetFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineWidgetFinder.first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, 'التفسير'));
      await tester.pumpAndSettle();

      expect(find.byType(QuranTafseerBottomSheet), findsOneWidget);
      // Verify Error state message and retry button
      expect(find.text('Tafseer load failed'), findsOneWidget);
      final retryFinder = find.widgetWithText(ElevatedButton, 'إعادة المحاولة');
      expect(retryFinder, findsOneWidget);

      // Ayah selection must still be preserved during error
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // Clear failure and tap retry
      fakeTafseerRepo.failNext = false;
      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      // Successfully recovers!
      final commentaryFinder = find.byKey(const Key('tafseer_commentary_text'));
      expect(commentaryFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(commentaryFinder);
      expect((textWidget.textSpan! as TextSpan).toPlainText(),
          contains('أبدأ قراءة القرآن'));
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      cubit.close();
    });
  });
}

