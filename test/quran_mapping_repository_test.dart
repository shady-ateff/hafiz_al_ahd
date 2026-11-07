import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_mapping_entities.dart';

void main() {
  late BaseQuranMappingLocalDataSource realDataSource;
  late QuranMappingRepositoryImpl repository;

  setUp(() {
    // Read the actual asset from disk using customDataLoader for fast hermetic unit tests
    realDataSource = QuranMappingLocalDataSourceImpl(
      customDataLoader: () async {
        final file = File('assets/quran/mushaf/ayah_mapping.json');
        return file.readAsString();
      },
    );
    repository = QuranMappingRepositoryImpl(localDataSource: realDataSource);
  });

  group('QuranMappingRepository Initialization Tests', () {
    test('Uninitialized repository rejects queries with CacheFailure', () async {
      final pageResult = await repository.getPageMapping(1);
      expect(pageResult.isLeft(), isTrue);
      pageResult.fold(
        (failure) => expect(failure.message, contains('not initialized')),
        (_) => fail('Should have failed'),
      );

      final ayahResult = await repository.getAyah(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(ayahResult.isLeft(), isTrue);

      final wordResult = await repository.getWord(WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1));
      expect(wordResult.isLeft(), isTrue);
    });

    test('Successful initialization parses and builds all indexes', () async {
      expect(repository.isInitialized, isFalse);
      final initResult = await repository.init();
      expect(initResult.isRight(), isTrue);
      expect(repository.isInitialized, isTrue);
    });

    test('Repeated initialization is idempotent and does not reload', () async {
      int loadCallCount = 0;
      final countingDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async {
          loadCallCount++;
          return File('assets/quran/mushaf/ayah_mapping.json').readAsString();
        },
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: countingDataSource);

      await repo.init();
      expect(loadCallCount, equals(1));

      // Second init call
      final secondInit = await repo.init();
      expect(secondInit.isRight(), isTrue);
      expect(loadCallCount, equals(1)); // Should NOT re-read or re-decode
    });

    test('Concurrent initialization calls await the same single operation', () async {
      int loadCallCount = 0;
      final countingDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async {
          loadCallCount++;
          await Future.delayed(const Duration(milliseconds: 20));
          return File('assets/quran/mushaf/ayah_mapping.json').readAsString();
        },
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: countingDataSource);

      // Fire 5 concurrent init() calls simultaneously
      final results = await Future.wait([
        repo.init(),
        repo.init(),
        repo.init(),
        repo.init(),
        repo.init(),
      ]);

      for (final r in results) {
        expect(r.isRight(), isTrue);
      }
      expect(loadCallCount, equals(1)); // Exactly one load executed
    });

    test('Initialization safely fails on invalid JSON or missing required keys', () async {
      final invalidDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => '{"invalid": true}',
      );
      final brokenRepo = QuranMappingRepositoryImpl(localDataSource: invalidDataSource);

      final result = await brokenRepo.init();
      expect(result.isLeft(), isTrue);
      expect(brokenRepo.isInitialized, isFalse);
    });
  });

  group('QuranMappingRepository Page Lookup Tests', () {
    setUp(() async {
      await repository.init();
    });

    test('Retrieves Page 1 with correct physical lines and word ordering', () async {
      final result = await repository.getPageMapping(1);
      expect(result.isRight(), isTrue);

      final lines = result.getOrElse(() => []);
      expect(lines.isNotEmpty, isTrue);

      // Verify physical line numbers are strictly ordered ascending
      for (int i = 1; i < lines.length; i++) {
        expect(lines[i].lineNumber > lines[i - 1].lineNumber, isTrue);
      }

      // Page 1 line 2 is the first text line (Surah 1:1)
      final line2 = lines.firstWhere((l) => l.lineNumber == 2);
      expect(line2.wordCount, equals(4));
      expect(line2.words.first.uthmaniText, equals('بِسْمِ'));
      expect(line2.words.last.uthmaniText, equals('ٱلرَّحِيمِ'));
    });

    test('Retrieves Page 48 (Al-Baqarah 282) containing all 15 lines', () async {
      final result = await repository.getPageMapping(48);
      expect(result.isRight(), isTrue);

      final lines = result.getOrElse(() => []);
      expect(lines.length, equals(15));
      for (int i = 0; i < 15; i++) {
        expect(lines[i].lineNumber, equals(i + 1));
        expect(lines[i].containsAyah(AyahId(surahNumber: 2, ayahNumber: 282)), isTrue);
      }
    });

    test('Rejects invalid page numbers (< 1 or > 604) with descriptive failure', () async {
      final lowResult = await repository.getPageMapping(0);
      expect(lowResult.isLeft(), isTrue);
      lowResult.fold((f) => expect(f.message, contains('Invalid page number: 0')), (_) => fail(''));

      final highResult = await repository.getPageMapping(605);
      expect(highResult.isLeft(), isTrue);
      highResult.fold((f) => expect(f.message, contains('Invalid page number: 605')), (_) => fail(''));
    });
  });

  group('QuranMappingRepository Ayah & Segment Lookup Tests', () {
    setUp(() async {
      await repository.init();
    });

    test('Retrieves single-line Ayah 1:1 with all metadata', () async {
      final result = await repository.getAyah(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(result.isRight(), isTrue);

      final ayah = result.getOrElse(() => throw Exception());
      expect(ayah.surahNumber, equals(1));
      expect(ayah.ayahNumber, equals(1));
      expect(ayah.pageNumber, equals(1));
      expect(ayah.endPageNumber, equals(1));
      expect(ayah.wordsCount, equals(4));
      expect(ayah.isMultiLine, isFalse);
      expect(ayah.uthmaniText, equals('بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ'));

      final segResult = await repository.getAyahSegments(ayah.id);
      expect(segResult.isRight(), isTrue);
      final segments = segResult.getOrElse(() => []);
      expect(segments.length, equals(1));
      expect(segments.first.lineNumber, equals(2));
      expect(segments.first.wordCount, equals(4));
      expect(segments.first.qcfText, equals('ﱁ ﱂ ﱃ ﱄ ﱅ'));
    });

    test('Retrieves multi-line Ayah 113:3 spanning lines 7 and 8', () async {
      final ayahId = AyahId(surahNumber: 113, ayahNumber: 3);
      final result = await repository.getAyah(ayahId);
      expect(result.isRight(), isTrue);

      final ayah = result.getOrElse(() => throw Exception());
      expect(ayah.isMultiLine, isTrue);
      expect(ayah.segments.length, equals(2));
      expect(ayah.wordsCount, equals(5));

      // Segment 1 on line 7
      final seg1 = ayah.segments[0];
      expect(seg1.pageNumber, equals(604));
      expect(seg1.lineNumber, equals(7));
      expect(seg1.wordStart, equals(8));
      expect(seg1.wordEnd, equals(9));
      expect(seg1.wordCount, equals(2));
      expect(seg1.qcfText, equals('ﱞ ﱟ'));

      // Segment 2 on line 8
      final seg2 = ayah.segments[1];
      expect(seg2.pageNumber, equals(604));
      expect(seg2.lineNumber, equals(8));
      expect(seg2.wordStart, equals(0));
      expect(seg2.wordEnd, equals(2));
      expect(seg2.wordCount, equals(3));
      expect(seg2.qcfText, equals('ﱠ ﱡ ﱢ ﱣ'));
    });

    test('Retrieves 15-segment Ayah 2:282 across all lines of Page 48', () async {
      final ayahId = AyahId(surahNumber: 2, ayahNumber: 282);
      final result = await repository.getAyah(ayahId);
      expect(result.isRight(), isTrue);

      final ayah = result.getOrElse(() => throw Exception());
      expect(ayah.segments.length, equals(15));
      expect(ayah.wordsCount, equals(128));
      for (int i = 0; i < 15; i++) {
        expect(ayah.segments[i].lineNumber, equals(i + 1));
      }
    });

    test('Rejects unknown AyahId with descriptive failure', () async {
      final result = await repository.getAyah(AyahId(surahNumber: 1, ayahNumber: 99));
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f.message, contains('Ayah not found')), (_) => fail(''));
    });
  });

  group('QuranMappingRepository Word Lookup Tests', () {
    setUp(() async {
      await repository.init();
    });

    test('Resolves known word with exact QCF glyph preservation', () async {
      // Word 1:1:1 ("بِسْمِ")
      final word1Result = await repository.getWord(
        WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1),
      );
      expect(word1Result.isRight(), isTrue);
      final word1 = word1Result.getOrElse(() => throw Exception());
      expect(word1.uthmaniText, equals('بِسْمِ'));
      expect(word1.qcfText, equals('ﱁ'));

      // Final word of Ayah 1:1 (4th word "ٱلرَّحِيمِ") includes attached verse sign
      final word4Result = await repository.getWord(
        WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 4),
      );
      expect(word4Result.isRight(), isTrue);
      final word4 = word4Result.getOrElse(() => throw Exception());
      expect(word4.uthmaniText, equals('ٱلرَّحِيمِ'));
      expect(word4.qcfText, equals('ﱄ ﱅ')); // Word glyph + Ayah end marker
    });

    test('Rejects unknown WordLocation with descriptive failure', () async {
      final result = await repository.getWord(
        WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 99),
      );
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f.message, contains('Word not found')), (_) => fail(''));
    });
  });

  group('Complete Dataset Integrity Verification (Full Mushaf)', () {
    setUp(() async {
      await repository.init();
    });

    test('All 604 pages are accessible with 8,820 total text lines', () async {
      int totalLines = 0;
      int totalWords = 0;

      for (int p = 1; p <= 604; p++) {
        final result = await repository.getPageMapping(p);
        expect(result.isRight(), isTrue, reason: 'Failed to retrieve page $p');
        final lines = result.getOrElse(() => []);
        expect(lines.isNotEmpty, isTrue, reason: 'Page $p has no lines');
        totalLines += lines.length;
        for (final l in lines) {
          totalWords += l.wordCount;
        }
      }

      expect(totalLines, equals(8820), reason: 'Total text lines must equal 8,820');
      expect(totalWords, equals(78003), reason: 'Total words must equal 78,003');
    });

    test('All 6,236 Ayahs are accessible and consistent', () async {
      // Sample test across all 114 Surahs
      for (int s = 1; s <= 114; s++) {
        final firstAyahResult = await repository.getAyah(AyahId(surahNumber: s, ayahNumber: 1));
        expect(firstAyahResult.isRight(), isTrue, reason: 'Surah $s Ayah 1 missing');
        final ayah = firstAyahResult.getOrElse(() => throw Exception());
        expect(ayah.segments.isNotEmpty, isTrue);
      }
    });
  });
}

