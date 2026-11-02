import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_bookmark_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_bookmark_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_bookmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late QuranBookmarkLocalDataSourceImpl localDataSource;
  late QuranBookmarkRepositoryImpl repository;

  final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
  final ayah2 = AyahId(surahNumber: 2, ayahNumber: 255);
  final ayah3 = AyahId(surahNumber: 112, ayahNumber: 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    localDataSource = QuranBookmarkLocalDataSourceImpl(sharedPreferences: prefs);
    repository = QuranBookmarkRepositoryImpl(localDataSource: localDataSource);
  });

  group('Phase 2.6.3.4 — QuranBookmarkRepository Tests', () {
    test('1. Add bookmark saves entity and retrieves it successfully', () async {
      final now = DateTime(2026, 11, 2, 10, 0);
      final addResult = await repository.addBookmark(
        ayahId: ayah1,
        pageNumber: 1,
        createdAt: now,
      );

      expect(addResult.isRight(), isTrue);
      addResult.fold((l) => fail('Should succeed'), (b) {
        expect(b.ayahId, equals(ayah1));
        expect(b.pageNumber, equals(1));
        expect(b.createdAt, equals(now));
      });

      final getResult = await repository.getBookmarks();
      expect(getResult.isRight(), isTrue);
      final bookmarks = getResult.getOrElse(() => []);
      expect(bookmarks.length, equals(1));
      expect(bookmarks.first.ayahId, equals(ayah1));
      expect(bookmarks.first.pageNumber, equals(1));
    });

    test('2. Duplicate prevention: adding same AyahId returns existing without creating duplicate', () async {
      final t1 = DateTime(2026, 11, 2, 10, 0);
      final t2 = DateTime(2026, 11, 2, 11, 0);

      await repository.addBookmark(ayahId: ayah2, pageNumber: 42, createdAt: t1);
      final secondAdd = await repository.addBookmark(ayahId: ayah2, pageNumber: 42, createdAt: t2);

      expect(secondAdd.isRight(), isTrue);
      final list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.createdAt, equals(t1)); // preserved original
    });

    test('3. Remove bookmark deletes the AyahId from persistence', () async {
      await repository.addBookmark(ayahId: ayah1, pageNumber: 1);
      await repository.addBookmark(ayahId: ayah2, pageNumber: 42);

      var list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(2));

      final removeResult = await repository.removeBookmark(ayah1);
      expect(removeResult.isRight(), isTrue);

      list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.ayahId, equals(ayah2));

      final isAyah1Bookmarked = (await repository.isBookmarked(ayah1)).getOrElse(() => true);
      expect(isAyah1Bookmarked, isFalse);
    });

    test('4. Toggle bookmark: adds when absent, removes when present', () async {
      // Step 1: toggle absent -> added (returns true)
      final toggle1 = await repository.toggleBookmark(ayahId: ayah3, pageNumber: 604);
      expect(toggle1.isRight(), isTrue);
      expect(toggle1.getOrElse(() => false), isTrue);

      var isBookmarked = (await repository.isBookmarked(ayah3)).getOrElse(() => false);
      expect(isBookmarked, isTrue);

      // Step 2: toggle present -> removed (returns false)
      final toggle2 = await repository.toggleBookmark(ayahId: ayah3, pageNumber: 604);
      expect(toggle2.isRight(), isTrue);
      expect(toggle2.getOrElse(() => true), isFalse);

      isBookmarked = (await repository.isBookmarked(ayah3)).getOrElse(() => true);
      expect(isBookmarked, isFalse);
    });

    test('5. Persistence after reinitialization: bookmarks survive repository recreation', () async {
      final t1 = DateTime(2026, 11, 2, 8, 30);
      await repository.addBookmark(ayahId: ayah1, pageNumber: 1, createdAt: t1);
      await repository.addBookmark(ayahId: ayah2, pageNumber: 42, createdAt: t1.add(const Duration(hours: 1)));

      // Re-create new DataSource and Repository instance from same SharedPreferences
      final newLocalDataSource = QuranBookmarkLocalDataSourceImpl(sharedPreferences: prefs);
      final newRepository = QuranBookmarkRepositoryImpl(localDataSource: newLocalDataSource);

      final result = await newRepository.getBookmarks();
      expect(result.isRight(), isTrue);
      final list = result.getOrElse(() => []);
      expect(list.length, equals(2));
      expect(list.any((b) => b.ayahId == ayah1), isTrue);
      expect(list.any((b) => b.ayahId == ayah2), isTrue);
    });

    test('6. Malformed JSON recovery: handles corrupt string, non-list, and missing fields gracefully', () async {
      // Sub-case A: Corrupted non-JSON string
      await prefs.setString(QuranBookmarkLocalDataSourceImpl.kQuranBookmarksKey, 'NOT_VALID_JSON{:::');
      var list = (await repository.getBookmarks()).getOrElse(() => [QuranBookmark(ayahId: ayah1, createdAt: DateTime.now())]);
      expect(list, isEmpty);

      // Sub-case B: Root is a JSON object instead of a list
      await prefs.setString(QuranBookmarkLocalDataSourceImpl.kQuranBookmarksKey, '{"some_key": 123}');
      list = (await repository.getBookmarks()).getOrElse(() => [QuranBookmark(ayahId: ayah1, createdAt: DateTime.now())]);
      expect(list, isEmpty);

      // Sub-case C: List containing both valid and corrupt item (missing fields)
      final mixedList = [
        {'ayah_id': '2:255', 'created_at': '2026-11-02T10:00:00.000Z', 'page_number': 42},
        {'bad_key': 'corrupted_value'},
        'string_instead_of_map',
      ];
      await prefs.setString(QuranBookmarkLocalDataSourceImpl.kQuranBookmarksKey, jsonEncode(mixedList));

      list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.ayahId, equals(ayah2));
      expect(list.first.pageNumber, equals(42));
    });

    test('7. Stable ordering: returns newest bookmarks first by createdAt descending', () async {
      final t1 = DateTime(2026, 11, 2, 8, 0);
      final t2 = DateTime(2026, 11, 2, 9, 0);
      final t3 = DateTime(2026, 11, 2, 10, 0);

      // Add in mixed order
      await repository.addBookmark(ayahId: ayah1, pageNumber: 1, createdAt: t1);
      await repository.addBookmark(ayahId: ayah3, pageNumber: 604, createdAt: t3);
      await repository.addBookmark(ayahId: ayah2, pageNumber: 42, createdAt: t2);

      final list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(3));
      expect(list[0].ayahId, equals(ayah3)); // newest (10:00)
      expect(list[1].ayahId, equals(ayah2)); // middle (09:00)
      expect(list[2].ayahId, equals(ayah1)); // oldest (08:00)
    });

    test('8. Custom name and color code are persisted and updated properly', () async {
      await repository.addBookmark(
        ayahId: ayah1,
        pageNumber: 1,
        name: 'فاصل ورد الحفظ',
        colorCode: 0xFF2E7D32,
      );

      var list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.first.name, equals('فاصل ورد الحفظ'));
      expect(list.first.colorCode, equals(0xFF2E7D32));

      // Update name and color
      await repository.addBookmark(
        ayahId: ayah1,
        pageNumber: 1,
        name: 'فاصل ورد التلاوة',
        colorCode: 0xFFD4AF37,
      );

      list = (await repository.getBookmarks()).getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.name, equals('فاصل ورد التلاوة'));
      expect(list.first.colorCode, equals(0xFFD4AF37));
    });
  });
}

