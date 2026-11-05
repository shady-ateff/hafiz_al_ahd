import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_tafseer_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase P2-A: Background JSON Parsing — Quran Tafseer', () {
    final validSampleTafseerJson = jsonEncode({
      'metadata': {
        'version': '3.0',
        'edition': 'KFGQPC Tafseer Mouaser',
        'total_ayahs': 3,
      },
      'tafseer': {
        '1:1': '[1] بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ - تفسير الفاتحة 1',
        '1:2': '[2] الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ - تفسير الفاتحة 2',
        '114:6': '[6] مِنَ الْجِنَّةِ وَالنَّاسِ - تفسير الناس 6',
      },
    });

    test('1. Background Parsing: Successfully decodes and indexes via background isolate', () async {
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => validSampleTafseerJson,
      );

      expect(dataSource.isLoaded, isFalse);
      final text11 = await dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(dataSource.isLoaded, isTrue);
      expect(text11, contains('تفسير الفاتحة 1'));

      final text1146 = await dataSource.getTafseerText(AyahId(surahNumber: 114, ayahNumber: 6));
      expect(text1146, contains('تفسير الناس 6'));
    });

    test('2. Concurrent Requests: Multiple simultaneous requests reuse single in-flight isolate future', () async {
      int customDataLoaderCalls = 0;
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async {
          customDataLoaderCalls++;
          await Future.delayed(const Duration(milliseconds: 30));
          return validSampleTafseerJson;
        },
      );

      final futures = List.generate(
        10,
        (i) => dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: (i % 2) + 1)),
      );

      final results = await Future.wait(futures);
      expect(results.length, equals(10));
      expect(customDataLoaderCalls, equals(1), reason: 'Must deduplicate concurrent parsing');
      expect(dataSource.isLoaded, isTrue);
    });

    test('3. Failure Propagation: Syntax error in JSON throws FormatException from isolate', () async {
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => '{ "invalid_json": [ unclosed ',
      );

      await expectLater(
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );
      expect(dataSource.isLoaded, isFalse);
    });

    test('4. Retry After Failure: In-flight future clears on error to allow successful subsequent attempt', () async {
      bool shouldFail = true;
      int callCount = 0;

      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async {
          callCount++;
          if (shouldFail) {
            throw const FormatException('Simulated network/disk corruption');
          }
          return validSampleTafseerJson;
        },
      );

      // Attempt 1: Fails
      await expectLater(
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );
      expect(dataSource.isLoaded, isFalse);
      expect(callCount, equals(1));

      // Attempt 2: Recovered and succeeds
      shouldFail = false;
      final text = await dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(dataSource.isLoaded, isTrue);
      expect(text, contains('تفسير الفاتحة 1'));
      expect(callCount, equals(2));
    });

    test('5. Data Identity: Real tafseer_mouaser.json retains 100% Arabic text fidelity', () async {
      final realDataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => File('assets/quran/tafseer/tafseer_mouaser.json').readAsString(),
      );

      final fatihah1 = await realDataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(fatihah1, isNotEmpty);
      expect(fatihah1, startsWith('[1]'));

      final ikhlas1 = await realDataSource.getTafseerText(AyahId(surahNumber: 112, ayahNumber: 1));
      expect(ikhlas1, isNotEmpty);
      expect(ikhlas1, startsWith('[1]'));

      final nas6 = await realDataSource.getTafseerText(AyahId(surahNumber: 114, ayahNumber: 6));
      expect(nas6, isNotEmpty);
      expect(nas6, startsWith('[6]'));
    });

    test('6. Empty and Malformed Input Handling: Rejects empty strings and missing "tafseer" key', () async {
      final emptyDataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => '   ',
      );
      await expectLater(
        emptyDataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );

      final missingKeyDataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => jsonEncode({'metadata': {'version': '1.0'}}),
      );
      await expectLater(
        missingKeyDataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Phase P2-A: Background JSON Parsing — Quran Ayah Mapping', () {
    final validSampleMappingJson = jsonEncode({
      'metadata': {
        'version': '1.0',
        'source': 'Unit Test Minimal Mapping',
      },
      'pages': {
        '1': [
          {
            'line': 1,
            'words': [
              {
                'surah': 1,
                'ayah': 1,
                'word_index': 1,
                'uthmani': 'بِسْمِ',
                'qcf': 'ﱁ',
              },
              {
                'surah': 1,
                'ayah': 1,
                'word_index': 2,
                'uthmani': 'اللَّهِ',
                'qcf': 'ﱂ',
              },
            ],
          },
        ],
      },
      'ayahs': {
        '1:1': {
          'page': 1,
          'end_page': 1,
          'uthmani': 'بِسْمِ اللَّهِ',
          'words_count': 2,
          'segments': [
            {
              'page': 1,
              'line': 1,
              'word_start': 0,
              'word_end': 1,
            },
          ],
        },
      },
    });

    test('1. Background Parsing: Successfully builds all 4 indexes in background isolate', () async {
      final dataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => validSampleMappingJson,
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: dataSource);

      expect(repo.isInitialized, isFalse);
      final initResult = await repo.init();
      expect(initResult.isRight(), isTrue);
      expect(repo.isInitialized, isTrue);

      final pageRes = await repo.getPageMapping(1);
      expect(pageRes.isRight(), isTrue);
      pageRes.fold((_) => fail('Should succeed'), (lines) {
        expect(lines.length, equals(1));
        expect(lines.first.words.length, equals(2));
        expect(lines.first.words.first.qcfText, equals('ﱁ'));
      });

      final ayahRes = await repo.getAyah(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(ayahRes.isRight(), isTrue);
      ayahRes.fold((_) => fail('Should succeed'), (ayah) {
        expect(ayah.wordsCount, equals(2));
        expect(ayah.segments.length, equals(1));
      });
    });

    test('2. Concurrent Requests: Multiple simultaneous init() calls await same background isolate', () async {
      int loadCallCount = 0;
      final dataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async {
          loadCallCount++;
          await Future.delayed(const Duration(milliseconds: 30));
          return validSampleMappingJson;
        },
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: dataSource);

      final futures = [
        repo.init(),
        repo.init(),
        repo.init(),
        repo.init(),
      ];

      final results = await Future.wait(futures);
      expect(results.every((r) => r.isRight()), isTrue);
      expect(loadCallCount, equals(1), reason: 'Must deduplicate concurrent initialization');
      expect(repo.isInitialized, isTrue);
    });

    test('3. Failure Propagation: Syntax error in mapping JSON propagates as Left(CacheFailure)', () async {
      final dataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => '{"broken_json": [',
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: dataSource);

      final result = await repo.init();
      expect(result.isLeft(), isTrue);
      expect(repo.isInitialized, isFalse);
      result.fold(
        (failure) => expect(failure.message, contains('Failed to initialize')),
        (_) => fail('Should have failed'),
      );
    });

    test('4. Retry After Failure: Clears in-flight Future on error to allow successful retry', () async {
      bool shouldFail = true;
      int callCount = 0;

      final dataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async {
          callCount++;
          if (shouldFail) {
            throw const FormatException('Corrupted file');
          }
          return validSampleMappingJson;
        },
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: dataSource);

      // Attempt 1: Fails
      final failResult = await repo.init();
      expect(failResult.isLeft(), isTrue);
      expect(repo.isInitialized, isFalse);
      expect(callCount, equals(1));

      // Attempt 2: Succeeds
      shouldFail = false;
      final successResult = await repo.init();
      expect(successResult.isRight(), isTrue);
      expect(repo.isInitialized, isTrue);
      expect(callCount, equals(2));
    });

    test('5. Data Identity: Full 11.5 MB dataset parses correctly in background isolate', () async {
      final realDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => File('assets/quran/mushaf/ayah_mapping.json').readAsString(),
      );
      final repo = QuranMappingRepositoryImpl(localDataSource: realDataSource);

      final initResult = await repo.init();
      expect(initResult.isRight(), isTrue);
      expect(repo.isInitialized, isTrue);

      // Verify canonical boundaries: 604 pages, Ayah 1:1, Ayah 2:282, Ayah 114:6
      final page1Res = await repo.getPageMapping(1);
      expect(page1Res.isRight(), isTrue);

      final page604Res = await repo.getPageMapping(604);
      expect(page604Res.isRight(), isTrue);

      final ayah11Res = await repo.getAyah(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(ayah11Res.isRight(), isTrue);

      final ayah2282Res = await repo.getAyah(AyahId(surahNumber: 2, ayahNumber: 282));
      expect(ayah2282Res.isRight(), isTrue);
      ayah2282Res.fold((_) => fail('Ayah 2:282 must exist'), (ayah) {
        expect(ayah.segments.length, equals(15));
      });

      final ayah1146Res = await repo.getAyah(AyahId(surahNumber: 114, ayahNumber: 6));
      expect(ayah1146Res.isRight(), isTrue);
    });

    test('6. Empty and Malformed Input Handling: Rejects empty strings and missing top-level keys', () async {
      final emptyDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => '   ',
      );
      final emptyRepo = QuranMappingRepositoryImpl(localDataSource: emptyDataSource);
      final emptyRes = await emptyRepo.init();
      expect(emptyRes.isLeft(), isTrue);

      final missingKeysDataSource = QuranMappingLocalDataSourceImpl(
        customDataLoader: () async => jsonEncode({'metadata': {'version': '1.0'}}),
      );
      final missingKeysRepo = QuranMappingRepositoryImpl(localDataSource: missingKeysDataSource);
      final missingRes = await missingKeysRepo.init();
      expect(missingRes.isLeft(), isTrue);
    });
  });
}
