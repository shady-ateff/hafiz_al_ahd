import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_clipboard_service.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_share_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_ayah_action_bottom_sheet.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_interactive_line_widget.dart';
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
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(AyahId ayahId) async =>
      const Right([]);

  @override
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(int pageNumber) async {
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

class TestQuranCubit extends QuranCubit {
  final Map<int, QuranState> _testPagesCache = {};

  TestQuranCubit({
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late MockQuranMappingRepo mockMappingRepo;
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

  group('Phase 2.6.2 — 1. QuranCubit.selectAyah API Tests', () {
    test('selectAyah sets selection, preserves on same Ayah, and replaces on different Ayah', () async {
      final cubit = TestQuranCubit(
        getQuranPageUseCase: mockPageUseCase,
        mappingRepository: mockMappingRepo,
      );

      await cubit.loadPage(1);
      expect(cubit.selectedAyahId, isNull);

      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final ayah2 = AyahId(surahNumber: 1, ayahNumber: 2);

      // 1. Select Ayah 1
      cubit.selectAyah(ayah1);
      expect(cubit.selectedAyahId, equals(ayah1));

      // 2. Select Ayah 1 again: PRESERVES selection (does not toggle to null!)
      cubit.selectAyah(ayah1);
      expect(cubit.selectedAyahId, equals(ayah1));

      // 3. Select Ayah 2: REPLACES selection
      cubit.selectAyah(ayah2);
      expect(cubit.selectedAyahId, equals(ayah2));

      // 4. Contrast with toggleAyahSelection: calling it on same Ayah clears to null
      cubit.toggleAyahSelection(ayah2);
      expect(cubit.selectedAyahId, isNull);

      cubit.close();
    });
  });

  group('Phase 2.6.2 — 2. QuranAyahActionBottomSheet UI Unit Tests', () {
    testWidgets('Renders header with Surah, Ayah, Page, and 4 action buttons, without Juz badge', (tester) async {
      bool tafseerTapped = false;
      bool copyTapped = false;
      bool shareTapped = false;
      bool bookmarkTapped = false;
      bool closeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranAyahActionBottomSheet(
              ayah: testAyah1,
              onTafseerTap: () => tafseerTapped = true,
              onCopyTap: () => copyTapped = true,
              onShareTap: () => shareTapped = true,
              onBookmarkTap: () => bookmarkTapped = true,
              onCloseTap: () => closeTapped = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header verification: Surah Name • Ayah Number • Page Number
      expect(find.textContaining('الفاتحة'), findsOneWidget);
      expect(find.textContaining('الآية 1'), findsOneWidget);
      expect(find.textContaining('صفحة 1'), findsOneWidget);

      // Verify Juz is NOT displayed in the BottomSheet
      expect(find.textContaining('الجزء'), findsNothing);

      // Verify Uthmani text is displayed
      expect(find.text(testAyah1.uthmaniText), findsOneWidget);

      // Verify 4 action buttons exist
      expect(find.text('التفسير'), findsOneWidget);
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.text('فاصلة'), findsOneWidget);

      // Verify button tap callbacks
      await tester.tap(find.text('التفسير'));
      expect(tafseerTapped, isTrue);

      await tester.tap(find.text('نسخ'));
      expect(copyTapped, isTrue);

      await tester.tap(find.text('مشاركة'));
      expect(shareTapped, isTrue);

      await tester.tap(find.text('فاصلة'));
      expect(bookmarkTapped, isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(closeTapped, isTrue);
    });
  });

  group('Phase 2.6.2 — 3. Gesture Arena & Tap Interception Unit Tests', () {
    testWidgets('Unselected word tap cascades to parent fullscreen toggle; selected word tap triggers reopening', (tester) async {
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final word1 = QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
        uthmaniText: 'بِسْمِ',
        qcfText: 'ﱁ',
      );
      final word2 = QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 2, wordIndex: 1),
        uthmaniText: 'ٱلْحَمْدُ',
        qcfText: 'ﱆ',
      );

      final line = QuranLineMapping(
        lineNumber: 1,
        pageNumber: 1,
        words: [word1, word2],
      );

      bool parentTapped = false;
      QuranWord? wordTapped;
      QuranWord? wordLongPressed;

      Widget buildTestHarness({AyahId? selectedAyahId}) {
        return MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () => parentTapped = true,
              child: QuranInteractiveLineWidget(
                line: line,
                fontFamily: 'QCF2001',
                dynamicHeight: 1.0,
                textColor: Colors.black,
                selectedAyahId: selectedAyahId,
                onWordTapped: (w) => wordTapped = w,
                onWordLongPressed: (w) => wordLongPressed = w,
              ),
            ),
          ),
        );
      }

      // Step A: When NO Ayah is selected:
      await tester.pumpWidget(buildTestHarness(selectedAyahId: null));
      await tester.pumpAndSettle();

      // Tap on word 1 (unselected): should bubble up to parent tap!
      parentTapped = false;
      wordTapped = null;
      await tester.tap(find.byType(QuranInteractiveLineWidget));
      await tester.pumpAndSettle();

      expect(parentTapped, isTrue, reason: 'Unselected word tap MUST cascade to parent fullscreen toggle');
      expect(wordTapped, isNull, reason: 'Unselected word must NOT trigger onWordTapped');

      // Step B: When Ayah 1 IS selected:
      await tester.pumpWidget(buildTestHarness(selectedAyahId: ayah1));
      await tester.pumpAndSettle();

      // Tap on word 1 (selected): recognizer accepts gesture, onWordTapped fires, parent is NOT tapped
      parentTapped = false;
      wordTapped = null;

      // Tap coordinates over word 1 (right side of line widget in RTL)
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      final lineRect = tester.getRect(lineFinder);
      await tester.tapAt(Offset(lineRect.right - (lineRect.width * 0.25), lineRect.center.dy));
      await tester.pumpAndSettle();

      expect(wordTapped, isNotNull, reason: 'Selected word tap MUST trigger onWordTapped to reopen sheet');
      expect(wordTapped?.ayahId, equals(ayah1));
      expect(parentTapped, isFalse);
    });
  });

  group('Phase 2.6.2 — 4. QuranScreen Route Lifecycle & Selection Persistence Tests', () {
    testWidgets('Long press selects Ayah and opens BottomSheet; dismissing preserves selection; page navigation clears', (tester) async {
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

      // Pre-load page 1 and page 2 so QuranScreen immediately displays page lines without Shimmer animation
      await cubit.loadPage(1);
      await cubit.loadPage(2);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: const MaterialApp(
            home: QuranScreen(initialPage: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Initial State: No selection, no BottomSheet
      expect(cubit.selectedAyahId, isNull);
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);

      // 2. Long press on QuranScreen: triggers selection and opens BottomSheet
      final pageViewFinder = find.byType(QuranInteractiveLineWidget);
      expect(pageViewFinder, findsWidgets);

      await tester.longPress(pageViewFinder.first);
      await tester.pumpAndSettle();

      // Selection is set
      expect(cubit.selectedAyahId, equals(testAyah1.id));
      // BottomSheet is open
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // 3. Dismiss BottomSheet via close button
      final closeBtnFinder = find.byIcon(Icons.close_rounded);
      expect(closeBtnFinder, findsOneWidget);
      await tester.tap(closeBtnFinder);
      await tester.pumpAndSettle();

      // BottomSheet is closed
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);
      // SELECTION IS PRESERVED!
      expect(cubit.selectedAyahId, equals(testAyah1.id), reason: 'Selection must be preserved after BottomSheet dismissal');

      // 4. Single tap on the selected Ayah: reopens BottomSheet!
      await tester.tap(pageViewFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget, reason: 'Single tap on selected Ayah must reopen BottomSheet');
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // 5. Duplicate Route Prevention: long press again on same Ayah while open does not push duplicate
      await tester.longPress(find.byType(QuranAyahActionBottomSheet), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      cubit.close();
    });
  });

  group('Phase 2.6.2.3 — Gesture Edge-Case & Recognizer Lifecycle Tests', () {
    testWidgets('1. Pointer cancellation cancels custom Timer and triggers no callbacks', (tester) async {
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final word1 = QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
        uthmaniText: 'بِسْمِ',
        qcfText: 'ﱁ',
      );
      final line = QuranLineMapping(
        lineNumber: 1,
        pageNumber: 1,
        words: [word1],
      );

      bool parentTapped = false;
      bool wordTapped = false;
      bool wordLongPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () => parentTapped = true,
              child: QuranInteractiveLineWidget(
                line: line,
                fontFamily: 'QCF2001',
                dynamicHeight: 1.0,
                textColor: Colors.black,
                selectedAyahId: ayah1,
                onWordTapped: (_) => wordTapped = true,
                onWordLongPressed: (_) => wordLongPressed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lineFinder = find.byType(QuranInteractiveLineWidget);
      final gesture = await tester.startGesture(tester.getCenter(lineFinder));

      // Advance time by 100ms (timer is active, not yet expired)
      await tester.pump(const Duration(milliseconds: 100));

      // Send real PointerCancelEvent
      await gesture.cancel();
      await tester.pumpAndSettle();

      // Advance time past the original 500ms LongPress deadline
      await tester.pump(const Duration(milliseconds: 600));

      expect(wordTapped, isFalse, reason: 'onTap must not be called after cancellation');
      expect(wordLongPressed, isFalse, reason: 'onLongPress must not be called after cancellation');
      expect(parentTapped, isFalse, reason: 'Parent fullscreen tap must not be called after cancellation');
    });

    testWidgets('2. Movement within permitted touch slop preserves gesture, while movement beyond slop cancels LongPress and Tap', (tester) async {
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final word1 = QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
        uthmaniText: 'بِسْمِ',
        qcfText: 'ﱁ',
      );
      final line = QuranLineMapping(
        lineNumber: 1,
        pageNumber: 1,
        words: [word1],
      );

      bool wordTapped = false;
      bool wordLongPressed = false;

      Widget buildWidget() => MaterialApp(
            home: Scaffold(
              body: QuranInteractiveLineWidget(
                line: line,
                fontFamily: 'QCF2001',
                dynamicHeight: 1.0,
                textColor: Colors.black,
                selectedAyahId: ayah1,
                onWordTapped: (_) => wordTapped = true,
                onWordLongPressed: (_) => wordLongPressed = true,
              ),
            ),
          );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(QuranInteractiveLineWidget));

      // Sub-test A: Movement within permitted touch slop (4 pixels < 18 pixels slop)
      wordTapped = false;
      wordLongPressed = false;
      final gestureA = await tester.startGesture(center);
      await gestureA.moveBy(const Offset(4.0, 0.0));
      // Hold past 500ms deadline -> should recognize LongPress
      await tester.pump(const Duration(milliseconds: 600));
      await gestureA.up();
      await tester.pumpAndSettle();

      expect(wordLongPressed, isTrue, reason: 'Small movement within touch slop must allow LongPress to trigger');
      expect(wordTapped, isFalse, reason: 'onTap must not fire when LongPress triggered within slop');

      // Sub-test B: Movement beyond permitted touch slop (30 pixels > 18 pixels slop)
      wordTapped = false;
      wordLongPressed = false;
      final gestureB = await tester.startGesture(center);
      await gestureB.moveBy(const Offset(30.0, 0.0));
      // Hold past 500ms deadline -> should be cancelled due to slop violation
      await tester.pump(const Duration(milliseconds: 600));
      await gestureB.up();
      await tester.pumpAndSettle();

      expect(wordLongPressed, isFalse, reason: 'Movement beyond slop must cancel LongPress');
      expect(wordTapped, isFalse, reason: 'Movement beyond slop must cancel Tap');
    });

    testWidgets('3. Widget rebuild updates callbacks and disposes old recognizers without stale executions', (tester) async {
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      final word1 = QuranWord(
        location: WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
        uthmaniText: 'بِسْمِ',
        qcfText: 'ﱁ',
      );
      final line = QuranLineMapping(
        lineNumber: 1,
        pageNumber: 1,
        words: [word1],
      );

      bool tapA = false;
      bool longPressA = false;
      bool tapB = false;
      bool longPressB = false;

      // 1. Build with Callbacks A
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLineWidget(
              line: line,
              fontFamily: 'QCF2001',
              dynamicHeight: 1.0,
              textColor: Colors.black,
              selectedAyahId: ayah1,
              onWordTapped: (_) => tapA = true,
              onWordLongPressed: (_) => longPressA = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Rebuild same widget configuration with Callbacks B
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranInteractiveLineWidget(
              line: line,
              fontFamily: 'QCF2001',
              dynamicHeight: 1.0,
              textColor: Colors.black,
              selectedAyahId: ayah1,
              onWordTapped: (_) => tapB = true,
              onWordLongPressed: (_) => longPressB = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Perform Tap interaction
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.tap(lineFinder);
      await tester.pumpAndSettle();

      expect(tapB, isTrue, reason: 'Callback B for Tap must execute after rebuild');
      expect(tapA, isFalse, reason: 'Stale Callback A for Tap must NOT execute');

      // 4. Perform LongPress interaction
      await tester.longPress(lineFinder);
      await tester.pumpAndSettle();

      expect(longPressB, isTrue, reason: 'Callback B for LongPress must execute after rebuild');
      expect(longPressA, isFalse, reason: 'Stale Callback A for LongPress must NOT execute');
    });
  });

  group('Phase 2.6.3.2 — Quran Ayah Copy Action Integration Tests', () {
    testWidgets('Tapping Copy button dismisses BottomSheet, preserves selection, copies formatted text, and shows success SnackBar', (tester) async {
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

      ClipboardData? capturedClipboardData;
      final mockClipboardService = QuranClipboardService(
        clipboardSetter: (data) async {
          capturedClipboardData = data;
        },
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              clipboardService: mockClipboardService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Long press line to open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // Tap Copy button
      final copyBtnFinder = find.text('نسخ');
      expect(copyBtnFinder, findsOneWidget);
      await tester.tap(copyBtnFinder);
      await tester.pumpAndSettle();

      // 1. BottomSheet dismissed
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);

      // 2. Selection preserved in QuranCubit
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // 3. Formatted text copied to clipboard
      expect(capturedClipboardData, isNotNull);
      expect(
        capturedClipboardData!.text,
        equals('﴿ ${testAyah1.uthmaniText} ﴾\n[سورة الفاتحة - الآية 1]'),
      );

      // 4. Success SnackBar displayed
      expect(find.text('تم نسخ الآية الكريمة بنجاح'), findsOneWidget);

      cubit.close();
    });

    testWidgets('Clipboard failure keeps BottomSheet open, preserves selection, shows error SnackBar, and allows retry', (tester) async {
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

      bool shouldFail = true;
      ClipboardData? capturedData;
      final retryableClipboardService = QuranClipboardService(
        clipboardSetter: (data) async {
          if (shouldFail) {
            throw Exception('Clipboard error');
          }
          capturedData = data;
        },
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              clipboardService: retryableClipboardService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Long press line to open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // 1. Initial attempt fails
      final copyBtnFinder = find.text('نسخ');
      await tester.tap(copyBtnFinder);
      await tester.pumpAndSettle();

      // BottomSheet REMAINS OPEN on failure
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // Selection preserved in cubit
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // Error SnackBar displayed and NO success SnackBar
      expect(find.text('فشل نسخ الآية، يرجى المحاولة مرة أخرى'), findsOneWidget);
      expect(find.text('تم نسخ الآية الكريمة بنجاح'), findsNothing);

      // 2. Retry succeeds: User taps Copy again
      shouldFail = false;
      await tester.tap(copyBtnFinder);
      await tester.pumpAndSettle();

      // BottomSheet closes on success
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);

      // Selection remains preserved
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // Success SnackBar is shown and clipboard captured data
      expect(find.text('تم نسخ الآية الكريمة بنجاح'), findsOneWidget);
      expect(capturedData, isNotNull);

      cubit.close();
    });

    testWidgets('No UI operations execute after screen is disposed during asynchronous clipboard operation', (tester) async {
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

      final completer = Completer<void>();
      final delayedClipboardService = QuranClipboardService(
        clipboardSetter: (data) => completer.future,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              clipboardService: delayedClipboardService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Long press line to open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // Tap Copy button: async operation starts and awaits completer
      final copyBtnFinder = find.text('نسخ');
      await tester.tap(copyBtnFinder);
      await tester.pump();

      // Dispose QuranScreen completely by replacing the widget tree
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pumpAndSettle();

      // Complete the clipboard operation while QuranScreen is unmounted
      completer.complete();
      await tester.pumpAndSettle();

      // Verify no SnackBar or post-unmount UI operation was attempted
      expect(find.text('تم نسخ الآية الكريمة بنجاح'), findsNothing);
      expect(find.text('فشل نسخ الآية، يرجى المحاولة مرة أخرى'), findsNothing);

      cubit.close();
    });
  });

  group('Phase 2.6.3.3 — Quran Ayah Share Action Integration Tests', () {
    testWidgets('Tapping Share button opens share options modal with Text and Image options', (tester) async {
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

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: const MaterialApp(
            home: QuranScreen(initialPage: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // Tap Share action button
      final shareBtnFinder = find.text('مشاركة');
      expect(shareBtnFinder, findsOneWidget);
      await tester.tap(shareBtnFinder);
      await tester.pumpAndSettle();

      // Verify share options modal appears with both options
      expect(find.text('مشاركة الآية الكريمة'), findsOneWidget);
      expect(find.text('مشاركة كنص'), findsOneWidget);
      expect(find.text('مشاركة كصورة'), findsOneWidget);

      cubit.close();
    });

    testWidgets('Selecting Share as Text invokes QuranShareService and handles success correctly', (tester) async {
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

      String? sharedText;
      final mockShareService = QuranShareService(
        textShare: (text, {subject}) async {
          sharedText = text;
          return const ShareResult('com.whatsapp', ShareResultStatus.success);
        },
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              shareService: mockShareService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      // Tap Share
      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();

      // Tap 'مشاركة كنص'
      await tester.tap(find.text('مشاركة كنص'));
      await tester.pumpAndSettle();

      // 1. Text is formatted correctly
      expect(sharedText, equals(QuranShareService.formatAyahForShare(testAyah1)));

      // 2. BottomSheet is closed on success
      expect(find.byType(QuranAyahActionBottomSheet), findsNothing);

      // 3. Selection is preserved
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // 4. Success SnackBar is displayed
      expect(find.text('تمت مشاركة الآية الكريمة بنجاح'), findsOneWidget);

      cubit.close();
    });

    testWidgets('Cancelling native share sheet does NOT show false success message and keeps selection active', (tester) async {
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

      final dismissingShareService = QuranShareService(
        textShare: (text, {subject}) async {
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              shareService: dismissingShareService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open bottom sheet
      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      // Tap Share -> Tap Share as text
      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مشاركة كنص'));
      await tester.pumpAndSettle();

      // BottomSheet remains open because user cancelled native share
      expect(find.byType(QuranAyahActionBottomSheet), findsOneWidget);

      // Selection remains active
      expect(cubit.selectedAyahId, equals(testAyah1.id));

      // NO false success SnackBar is displayed!
      expect(find.text('تمت مشاركة الآية الكريمة بنجاح'), findsNothing);

      cubit.close();
    });

    testWidgets('Disposing screen during async share operation causes no UI access after disposal', (tester) async {
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

      final completer = Completer<ShareResult>();
      final delayedShareService = QuranShareService(
        textShare: (text, {subject}) => completer.future,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranSettingsCubit>(
              create: (_) => QuranSettingsCubit(sharedPreferences: prefs),
            ),
            BlocProvider<QuranCubit>.value(value: cubit),
          ],
          child: MaterialApp(
            home: QuranScreen(
              initialPage: 1,
              shareService: delayedShareService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final lineFinder = find.byType(QuranInteractiveLineWidget);
      await tester.longPress(lineFinder.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();

      // Tap share as text: starts async operation awaiting completer
      await tester.tap(find.text('مشاركة كنص'));
      await tester.pump();

      // Unmount QuranScreen completely
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pumpAndSettle();

      // Complete share operation while screen is unmounted
      completer.complete(const ShareResult('com.whatsapp', ShareResultStatus.success));
      await tester.pumpAndSettle();

      // Verify no SnackBar was attempted on unmounted tree
      expect(find.text('تمت مشاركة الآية الكريمة بنجاح'), findsNothing);

      cubit.close();
    });
  });
}
