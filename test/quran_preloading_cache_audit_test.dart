import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';

class CountingFakeQuranRepository implements BaseQuranRepository {
  final Map<int, QuranPage> pages;
  final Map<int, int> fetchCounts = {};

  CountingFakeQuranRepository(this.pages);

  @override
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber) async {
    fetchCounts[pageNumber] = (fetchCounts[pageNumber] ?? 0) + 1;
    final page = pages[pageNumber];
    if (page != null) return Right(page);
    return Left(CacheFailure(message: 'Page not found'));
  }
}

class TestAuditQuranCubit extends QuranCubit {
  TestAuditQuranCubit({
    required super.getQuranPageUseCase,
    super.mappingRepository,
  });

  @override
  Future<void> initFonts() async {
    // No-op for tests
  }
}

void main() {
  late CountingFakeQuranRepository repository;
  late QuranMappingRepositoryImpl mappingRepository;
  late Map<int, QuranPage> allPages;

  setUpAll(() async {
    final dataSource = QuranMappingLocalDataSourceImpl(
      customDataLoader: () async =>
          File('assets/quran/mushaf/ayah_mapping.json').readAsString(),
    );
    mappingRepository = QuranMappingRepositoryImpl(localDataSource: dataSource);
    await mappingRepository.init();

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

  group('Phase 2.5 — Step 5: Preloading & Cache Integrity Audit', () {
    late TestAuditQuranCubit cubit;

    setUp(() {
      repository = CountingFakeQuranRepository(allPages);
      final useCase = GetQuranPageUseCase(repository);
      cubit = TestAuditQuranCubit(
        getQuranPageUseCase: useCase,
        mappingRepository: mappingRepository,
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('1. Active State Isolation: preloadPage does NOT emit, change page, or alter selection',
        () async {
      final emittedStates = <QuranState>[];
      final subscription = cubit.stream.listen(emittedStates.add);

      // Load Page 1
      await cubit.loadPage(1);
      final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
      cubit.toggleAyahSelection(ayah1);
      await pumpEventQueue();

      expect(cubit.state, isA<QuranPageLoaded>());
      final activeBefore = cubit.state as QuranPageLoaded;
      expect(activeBefore.page.pageNumber, equals(1));
      expect(activeBefore.selectedAyahId, equals(ayah1));
      final emitCountBefore = emittedStates.length;
      expect(emitCountBefore, equals(2));

      // Act: Preload Page 2
      await cubit.preloadPage(2);
      await pumpEventQueue();

      // Assert:
      // 1. No new state was emitted by preloadPage
      expect(emittedStates.length, equals(emitCountBefore));
      expect(
        emittedStates.any(
            (s) => s is QuranPageLoaded && s.page.pageNumber == 2),
        isFalse,
      );
      // 2. Active state is still Page 1
      expect(cubit.state, equals(activeBefore));
      expect((cubit.state as QuranPageLoaded).page.pageNumber, equals(1));
      // 3. Selection on Page 1 is strictly preserved
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayah1));
      // 4. Page 2 is now in cache and ready
      final cachedP2 = cubit.getCachedPage(2);
      expect(cachedP2, isNotNull);
      expect(cachedP2!.page.pageNumber, equals(2));
      expect(cachedP2.selectedAyahId, isNull);

      await subscription.cancel();
    });

    test('2. Cache Integrity: Existing cached pages are not reloaded, duplicates handled safely',
        () async {
      // Preload Page 2
      await cubit.preloadPage(2);
      expect(repository.fetchCounts[2], equals(1));

      // Preload Page 2 again (must be a no-op that reuses cache)
      await cubit.preloadPage(2);
      expect(repository.fetchCounts[2], equals(1),
          reason: 'Subsequent preload of same page must NOT hit repository again');

      // Load Page 2 (must be emitted directly from cache without hitting repository)
      await cubit.loadPage(2);
      expect(repository.fetchCounts[2], equals(1),
          reason: 'loadPage must serve directly from cache');
      expect((cubit.state as QuranPageLoaded).page.pageNumber, equals(2));
    });

    test('3. Selection Targeting: pageNumber targeting updates target page and emits new state',
        () async {
      await cubit.loadPage(1);
      await cubit.preloadPage(2);

      final ayahAlBaqarah = AyahId(surahNumber: 2, ayahNumber: 1);

      // Target Page 2 explicitly
      cubit.toggleAyahSelection(ayahAlBaqarah, pageNumber: 2);

      // Page 2 in cache must now have the selection
      final cachedP2 = cubit.getCachedPage(2);
      expect(cachedP2?.selectedAyahId, equals(ayahAlBaqarah));

      // Emitted state is updated to Page 2 with selectedAyahId
      expect(cubit.state, isA<QuranPageLoaded>());
      expect((cubit.state as QuranPageLoaded).page.pageNumber, equals(2));
      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahAlBaqarah));
    });

    test('4. Selection Targeting: Invalid / nonexistent pageNumber is handled safely',
        () {
      // Target a page that is not loaded/cached (e.g. Page 999)
      final dummyAyah = AyahId(surahNumber: 1, ayahNumber: 1);
      expect(
        () => cubit.toggleAyahSelection(dummyAyah, pageNumber: 999),
        returnsNormally,
      );
    });

    test('5. Navigation Stress Test: Rapid navigation across multiple pages with concurrent preloads',
        () async {
      final pagesSequence = [1, 2, 3, 4, 3, 2, 1];

      for (final p in pagesSequence) {
        cubit.clearSelection();
        await cubit.loadPage(p);

        // Preload adjacent pages concurrently
        if (p < 604) cubit.preloadPage(p + 1);
        if (p > 1) cubit.preloadPage(p - 1);

        // Verify active state always matches requested page
        expect(cubit.state, isA<QuranPageLoaded>());
        final loaded = cubit.state as QuranPageLoaded;
        expect(loaded.page.pageNumber, equals(p));
        // Verify no stale selection carried over
        expect(loaded.selectedAyahId, isNull);
      }
    });

    test('6. Immediate selection after page becomes visible is consistent',
        () async {
      // User loads Page 48 (Al-Baqarah 2:282)
      await cubit.loadPage(48);
      expect((cubit.state as QuranPageLoaded).page.pageNumber, equals(48));

      // Immediately select Ayah 2:282
      final ayahDayn = AyahId(surahNumber: 2, ayahNumber: 282);
      cubit.toggleAyahSelection(ayahDayn);

      expect((cubit.state as QuranPageLoaded).selectedAyahId, equals(ayahDayn));
      expect(cubit.getCachedPage(48)?.selectedAyahId, equals(ayahDayn));

      // User turns to Page 49 -> selection must clear
      cubit.clearSelection();
      await cubit.loadPage(49);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);

      // User turns back to Page 48 -> must have null selection (no stale highlight)
      await cubit.loadPage(48);
      expect((cubit.state as QuranPageLoaded).selectedAyahId, isNull);
    });
  });
}

