import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';

class MockQuranRepository implements BaseQuranRepository {
  final Map<int, QuranPage> pages;
  MockQuranRepository(this.pages);

  @override
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber) async {
    final page = pages[pageNumber];
    if (page != null) return Right(page);
    return Left(CacheFailure(message: 'Page not found'));
  }
}

class TestSelectionQuranCubit extends QuranCubit {
  TestSelectionQuranCubit({required super.getQuranPageUseCase});

  @override
  Future<void> initFonts() async {
    // Avoid network / disk fonts initialization in tests
  }
}

void main() {
  final ayahA = AyahId(surahNumber: 2, ayahNumber: 1);
  final ayahB = AyahId(surahNumber: 2, ayahNumber: 2);

  final dummyPage1 = QuranPage(
    pageNumber: 1,
    lines: [
      const QuranLine(
        lineNumber: 1,
        surahNumber: 1,
        text: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      ),
    ],
  );

  final dummyPage2 = QuranPage(
    pageNumber: 2,
    lines: [
      const QuranLine(
        lineNumber: 1,
        surahNumber: 2,
        text: 'الٓمٓ ۝١ ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ',
      ),
    ],
  );

  final dummyMappings = <QuranLineMapping>[
    QuranLineMapping(
      lineNumber: 1,
      pageNumber: 2,
      words: [
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 1, wordIndex: 1),
          qcfText: 'ﭑ',
          uthmaniText: 'الٓمٓ',
        ),
        QuranWord(
          location: WordLocation(surahNumber: 2, ayahNumber: 2, wordIndex: 1),
          qcfText: 'ﭓ',
          uthmaniText: 'ذَٰلِكَ',
        ),
      ],
    ),
  ];

  group('Phase 2.5 — Step 2: Selection State & copyWith Semantics', () {
    test('1. Initial selection is null on QuranPageLoaded', () {
      final state = QuranPageLoaded(
        page: dummyPage2,
        isFontLoaded: true,
        lineMappings: dummyMappings,
      );

      expect(state.selectedAyahId, isNull);
    });

    test('2. copyWith preserves selection when omitted', () {
      final initial = QuranPageLoaded(
        page: dummyPage2,
        isFontLoaded: true,
        lineMappings: dummyMappings,
        selectedAyahId: ayahA,
      );

      final updated = initial.copyWith(isFontLoaded: false);

      expect(updated.selectedAyahId, equals(ayahA));
      expect(updated.isFontLoaded, isFalse);
      expect(updated.page, equals(dummyPage2));
    });

    test('3. copyWith clears selection when selectedAyahId: null is passed', () {
      final initial = QuranPageLoaded(
        page: dummyPage2,
        isFontLoaded: true,
        lineMappings: dummyMappings,
        selectedAyahId: ayahA,
      );

      final updated = initial.copyWith(selectedAyahId: null);

      expect(updated.selectedAyahId, isNull);
      expect(updated.page, equals(dummyPage2));
      expect(updated.isFontLoaded, isTrue);
    });

    test('4. copyWith clears selection when clearSelectedAyah: true is passed', () {
      final initial = QuranPageLoaded(
        page: dummyPage2,
        isFontLoaded: true,
        lineMappings: dummyMappings,
        selectedAyahId: ayahA,
      );

      final updated = initial.copyWith(clearSelectedAyah: true);

      expect(updated.selectedAyahId, isNull);
    });

    test('5. copyWith updates selection to new AyahId', () {
      final initial = QuranPageLoaded(
        page: dummyPage2,
        isFontLoaded: true,
        lineMappings: dummyMappings,
        selectedAyahId: ayahA,
      );

      final updated = initial.copyWith(selectedAyahId: ayahB);

      expect(updated.selectedAyahId, equals(ayahB));
    });

    test('6. QuranPageLoaded equality honors selectedAyahId', () {
      final state1 = QuranPageLoaded(
        page: dummyPage2,
        selectedAyahId: ayahA,
      );
      final state2 = QuranPageLoaded(
        page: dummyPage2,
        selectedAyahId: ayahA,
      );
      final state3 = QuranPageLoaded(
        page: dummyPage2,
        selectedAyahId: ayahB,
      );

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
    });
  });

  group('Phase 2.5 — Step 2: Cubit Selection Management & Cache Consistency', () {
    late MockQuranRepository repository;
    late GetQuranPageUseCase useCase;
    late TestSelectionQuranCubit cubit;

    setUp(() {
      repository = MockQuranRepository({
        1: dummyPage1,
        2: dummyPage2,
      });
      useCase = GetQuranPageUseCase(repository);
      cubit = TestSelectionQuranCubit(getQuranPageUseCase: useCase);
    });

    tearDown(() {
      cubit.close();
    });

    test('7. Initial page load has null selection', () async {
      await cubit.loadPage(2);

      expect(cubit.state, isA<QuranPageLoaded>());
      final loadedState = cubit.state as QuranPageLoaded;
      expect(loadedState.selectedAyahId, isNull);
    });

    test('8. Selecting Ayah A selects Ayah A', () async {
      await cubit.loadPage(2);
      cubit.toggleAyahSelection(ayahA);

      final loadedState = cubit.state as QuranPageLoaded;
      expect(loadedState.selectedAyahId, equals(ayahA));
    });

    test('9. Selecting Ayah B replaces Ayah A', () async {
      await cubit.loadPage(2);
      cubit.toggleAyahSelection(ayahA);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahA));

      cubit.toggleAyahSelection(ayahB);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahB));
    });

    test('10. Selecting Ayah A again toggles and clears it', () async {
      await cubit.loadPage(2);
      cubit.toggleAyahSelection(ayahA);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahA));

      cubit.toggleAyahSelection(ayahA);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);
    });

    test('11. Explicitly calling clearSelection() clears existing selection', () async {
      await cubit.loadPage(2);
      cubit.toggleAyahSelection(ayahA);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahA));

      cubit.clearSelection();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);
    });

    test('12. Calling clearSelection() when selection is already null is a safe no-op', () async {
      await cubit.loadPage(2);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);

      cubit.clearSelection();
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);
    });

    test('13. Calling selection methods when state is not QuranPageLoaded is safe', () {
      // Current state is QuranInitial
      expect(cubit.state, isA<QuranInitial>());
      expect(() => cubit.toggleAyahSelection(ayahA), returnsNormally);
      expect(() => cubit.clearSelection(), returnsNormally);
      expect(cubit.state, isA<QuranInitial>());
    });

    test('14. Existing page data remains unchanged after selection updates', () async {
      await cubit.loadPage(2);
      final before = cubit.state as QuranPageLoaded;

      cubit.toggleAyahSelection(ayahA);
      final after = cubit.state as QuranPageLoaded;

      expect(after.page, equals(before.page));
      expect(after.isFontLoaded, equals(before.isFontLoaded));
      expect(after.lineMappings, equals(before.lineMappings));
    });

    test('15. Cache consistency: getCachedPage matches active state selection', () async {
      await cubit.loadPage(2);

      // Select Ayah A
      cubit.toggleAyahSelection(ayahA);
      expect(cubit.getCachedPage(2)?.selectedAyahId, equals(ayahA));
      expect(cubit.getCachedPage(2)?.selectedAyahId, equals((cubit.state as QuranPageLoaded).selectedAyahId));

      // Clear selection
      cubit.clearSelection();
      expect(cubit.getCachedPage(2)?.selectedAyahId, isNull);
      expect(cubit.getCachedPage(2)?.selectedAyahId, equals((cubit.state as QuranPageLoaded).selectedAyahId));
    });

    test('16. No stale selection appears after loading a cached page', () async {
      // 1. Load Page 1 and select Ayah A
      await cubit.loadPage(1);
      cubit.toggleAyahSelection(ayahA);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahA));

      // 2. Navigate away to Page 2
      await cubit.loadPage(2);
      expect((cubit.state as QuranPageLoaded).page.pageNumber, equals(2));
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);

      // 3. Navigate back to Page 1 from cache
      await cubit.loadPage(1);
      final reloadedPage1 = cubit.state as QuranPageLoaded;

      expect(reloadedPage1.page.pageNumber, equals(1));
      // Stale selection must NOT be restored
      expect(reloadedPage1.selectedAyahId, isNull);
    });

    test('17. Ayah resolution directly from QuranWord.ayahId', () {
      final word = dummyMappings.first.words.first;
      expect(word.ayahId, equals(ayahA));

      // Direct comparison with selection state
      final currentSelection = ayahA;
      final isWordSelected = word.ayahId == currentSelection;
      expect(isWordSelected, isTrue);

      final otherWord = dummyMappings.first.words[1];
      expect(otherWord.ayahId == currentSelection, isFalse);
    });
  });
}
