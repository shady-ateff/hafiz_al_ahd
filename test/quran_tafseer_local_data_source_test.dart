import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/exception.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_tafseer_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';

void main() {
  group('QuranTafseerLocalDataSourceImpl Unit Tests', () {
    final sampleJson = jsonEncode({
      'metadata': {
        'version': '3.0',
        'edition': 'KFGQPC Tafseer Mouaser',
        'total_ayahs': 2,
      },
      'tafseer': {
        '1:1': '[1] بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ تفسير الآية الأولى.',
        '1:2': '[2] الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ تفسير الآية الثانية.',
      },
    });

    test('1. Initial state is not loaded', () {
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => sampleJson,
      );

      expect(dataSource.isLoaded, isFalse);
    });

    test('2. Loads data lazily on first call and caches in memory', () async {
      int loadCount = 0;
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async {
          loadCount++;
          return sampleJson;
        },
      );

      expect(dataSource.isLoaded, isFalse);
      expect(loadCount, equals(0));

      final text11 = await dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(text11, contains('تفسير الآية الأولى'));
      expect(dataSource.isLoaded, isTrue);
      expect(loadCount, equals(1));

      // Second call uses in-memory cache without calling loader again
      final text12 = await dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 2));
      expect(text12, contains('تفسير الآية الثانية'));
      expect(loadCount, equals(1));
    });

    test('3. Throws CacheException when Ayah is not in dataset', () async {
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => sampleJson,
      );

      await expectLater(
        dataSource.getTafseerText(AyahId(surahNumber: 2, ayahNumber: 1)),
        throwsA(isA<CacheException>()),
      );
    });

    test('4. Concurrency protection: simultaneous calls invoke loader exactly once', () async {
      int loadCount = 0;
      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async {
          loadCount++;
          await Future.delayed(const Duration(milliseconds: 20));
          return sampleJson;
        },
      );

      // Launch 5 simultaneous requests
      final futures = [
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 2)),
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 2)),
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
      ];

      final results = await Future.wait(futures);

      expect(results.length, equals(5));
      expect(loadCount, equals(1), reason: 'Shared Future must prevent duplicate loading');
      expect(dataSource.isLoaded, isTrue);
    });

    test('5. Resets loading future on failure to allow subsequent retry', () async {
      bool shouldFail = true;
      int loadCount = 0;

      final dataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async {
          loadCount++;
          if (shouldFail) {
            throw Exception('Disk read error');
          }
          return sampleJson;
        },
      );

      // First attempt fails
      await expectLater(
        dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<Exception>()),
      );
      expect(dataSource.isLoaded, isFalse);
      expect(loadCount, equals(1));

      // Fix failure and retry
      shouldFail = false;
      final text = await dataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1));
      expect(text, contains('تفسير الآية الأولى'));
      expect(dataSource.isLoaded, isTrue);
      expect(loadCount, equals(2));
    });

    test('6. Throws FormatException on empty or invalid asset JSON', () async {
      final emptyDataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => '',
      );
      await expectLater(
        emptyDataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );

      final invalidStructureDataSource = QuranTafseerLocalDataSourceImpl(
        customDataLoader: () async => jsonEncode({'invalid_key': 123}),
      );
      await expectLater(
        invalidStructureDataSource.getTafseerText(AyahId(surahNumber: 1, ayahNumber: 1)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

