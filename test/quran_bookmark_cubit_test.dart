import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_bookmark.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_bookmark_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_bookmarks_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/remove_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/toggle_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_state.dart';

class MockQuranBookmarkRepository implements QuranBookmarkRepository {
  final List<QuranBookmark> _inMemoryBookmarks = [];
  bool simulateFailure = false;

  @override
  Future<Either<Failure, List<QuranBookmark>>> getBookmarks() async {
    if (simulateFailure) return Left(CacheFailure(message: 'Disk read failure'));
    return Right(List.unmodifiable(_inMemoryBookmarks));
  }

  @override
  Future<Either<Failure, QuranBookmark>> addBookmark({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  }) async {
    if (simulateFailure) return Left(CacheFailure(message: 'Disk write failure'));
    final b = QuranBookmark(
      ayahId: ayahId,
      createdAt: createdAt ?? DateTime.now(),
      pageNumber: pageNumber,
      name: name,
      colorCode: colorCode,
    );
    _inMemoryBookmarks.add(b);
    return Right(b);
  }

  @override
  Future<Either<Failure, void>> removeBookmark(AyahId ayahId) async {
    if (simulateFailure) return Left(CacheFailure(message: 'Disk remove failure'));
    _inMemoryBookmarks.removeWhere((b) => b.ayahId == ayahId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, bool>> isBookmarked(AyahId ayahId) async {
    if (simulateFailure) return Left(CacheFailure(message: 'Disk check failure'));
    return Right(_inMemoryBookmarks.any((b) => b.ayahId == ayahId));
  }

  @override
  Future<Either<Failure, bool>> toggleBookmark({
    required AyahId ayahId,
    int? pageNumber,
    String? name,
    int? colorCode,
  }) async {
    if (simulateFailure) return Left(CacheFailure(message: 'Disk toggle failure'));
    final idx = _inMemoryBookmarks.indexWhere((b) => b.ayahId == ayahId);
    if (idx != -1) {
      _inMemoryBookmarks.removeAt(idx);
      return const Right(false);
    } else {
      _inMemoryBookmarks.add(QuranBookmark(
        ayahId: ayahId,
        createdAt: DateTime.now(),
        pageNumber: pageNumber,
        name: name,
        colorCode: colorCode,
      ));
      return const Right(true);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQuranBookmarkRepository mockRepo;
  late QuranBookmarkCubit cubit;

  final ayah1 = AyahId(surahNumber: 1, ayahNumber: 1);
  final ayah2 = AyahId(surahNumber: 2, ayahNumber: 255);

  setUp(() {
    mockRepo = MockQuranBookmarkRepository();
    cubit = QuranBookmarkCubit(
      getBookmarksUseCase: GetQuranBookmarksUseCase(mockRepo),
      toggleBookmarkUseCase: ToggleQuranBookmarkUseCase(mockRepo),
      removeBookmarkUseCase: RemoveQuranBookmarkUseCase(mockRepo),
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('Phase 2.6.3.4 — QuranBookmarkCubit Tests', () {
    test('1. Initial state is QuranBookmarkInitial and isAyahBookmarked returns false', () {
      expect(cubit.state, isA<QuranBookmarkInitial>());
      expect(cubit.isAyahBookmarked(ayah1), isFalse);
    });

    test('2. loadBookmarks emits [QuranBookmarkLoading, QuranBookmarkLoaded] on success', () async {
      mockRepo._inMemoryBookmarks.add(QuranBookmark(
        ayahId: ayah1,
        createdAt: DateTime(2026, 11, 2),
        pageNumber: 1,
      ));

      final expectedStates = [
        isA<QuranBookmarkLoading>(),
        isA<QuranBookmarkLoaded>().having(
          (s) => s.bookmarks.length,
          'bookmarks length',
          1,
        ),
      ];

      expectLater(cubit.stream, emitsInOrder(expectedStates));

      await cubit.loadBookmarks();
      expect(cubit.isAyahBookmarked(ayah1), isTrue);
      expect(cubit.isAyahBookmarked(ayah2), isFalse);
    });

    test('3. toggleBookmark successfully adds then removes bookmark, updating state synchronously', () async {
      await cubit.loadBookmarks();
      expect(cubit.isAyahBookmarked(ayah1), isFalse);

      // Toggle Add
      final addedResult = await cubit.toggleBookmark(ayah1, pageNumber: 1);
      expect(addedResult, isTrue);
      expect(cubit.isAyahBookmarked(ayah1), isTrue);
      expect((cubit.state as QuranBookmarkLoaded).bookmarks.length, equals(1));

      // Toggle Remove
      final removedResult = await cubit.toggleBookmark(ayah1, pageNumber: 1);
      expect(removedResult, isFalse);
      expect(cubit.isAyahBookmarked(ayah1), isFalse);
      expect((cubit.state as QuranBookmarkLoaded).bookmarks.length, equals(0));
    });

    test('4. removeBookmark removes specific bookmark and refreshes loaded state', () async {
      await cubit.toggleBookmark(ayah1, pageNumber: 1);
      await cubit.toggleBookmark(ayah2, pageNumber: 42);
      expect((cubit.state as QuranBookmarkLoaded).bookmarks.length, equals(2));

      await cubit.removeBookmark(ayah1);
      expect(cubit.isAyahBookmarked(ayah1), isFalse);
      expect(cubit.isAyahBookmarked(ayah2), isTrue);
      expect((cubit.state as QuranBookmarkLoaded).bookmarks.length, equals(1));
    });

    test('5. Error handling emits QuranBookmarkError when repository fails', () async {
      mockRepo.simulateFailure = true;

      final expectedStates = [
        isA<QuranBookmarkLoading>(),
        isA<QuranBookmarkError>().having(
          (s) => s.message,
          'error message',
          contains('Disk read failure'),
        ),
      ];

      expectLater(cubit.stream, emitsInOrder(expectedStates));

      await cubit.loadBookmarks();
    });

    test('6. Concurrent toggle operations maintain consistency without crashing', () async {
      await cubit.loadBookmarks();

      // Fire multiple toggle calls
      final futures = [
        cubit.toggleBookmark(ayah1, pageNumber: 1),
        cubit.toggleBookmark(ayah2, pageNumber: 42),
      ];

      final results = await Future.wait(futures);
      expect(results.length, equals(2));
      expect(cubit.state, isA<QuranBookmarkLoaded>());
      final loaded = cubit.state as QuranBookmarkLoaded;
      expect(loaded.bookmarks.length, equals(2));
      expect(cubit.isAyahBookmarked(ayah1), isTrue);
      expect(cubit.isAyahBookmarked(ayah2), isTrue);
    });
  });
}

