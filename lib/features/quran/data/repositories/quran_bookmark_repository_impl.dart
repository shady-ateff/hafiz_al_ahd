import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_bookmark.dart';
import '../../domain/repositories/quran_bookmark_repository.dart';
import '../datasources/quran_bookmark_local_data_source.dart';
import '../models/quran_bookmark_model.dart';

class QuranBookmarkRepositoryImpl implements QuranBookmarkRepository {
  final BaseQuranBookmarkLocalDataSource localDataSource;

  QuranBookmarkRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<QuranBookmark>>> getBookmarks() async {
    try {
      final models = await localDataSource.getBookmarks();
      // Stable predictable sort: newest created first, then surah, then ayah
      models.sort((a, b) {
        final cmp = b.createdAt.compareTo(a.createdAt);
        if (cmp != 0) return cmp;
        final surahCmp = a.ayahId.surahNumber.compareTo(b.ayahId.surahNumber);
        if (surahCmp != 0) return surahCmp;
        return a.ayahId.ayahNumber.compareTo(b.ayahId.ayahNumber);
      });
      return Right(models);
    } catch (e) {
      return Left(CacheFailure(message: 'Failed to retrieve bookmarks: $e'));
    }
  }

  @override
  Future<Either<Failure, QuranBookmark>> addBookmark({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  }) async {
    try {
      final models = await localDataSource.getBookmarks();
      final existingIndex = models.indexWhere((b) => b.ayahId == ayahId);

      if (existingIndex != -1) {
        final existing = models[existingIndex];
        final updated = QuranBookmarkModel(
          ayahId: ayahId,
          createdAt: existing.createdAt,
          pageNumber: pageNumber ?? existing.pageNumber,
          name: name ?? existing.name,
          colorCode: colorCode ?? existing.colorCode,
        );
        models[existingIndex] = updated;
        await localDataSource.saveBookmarks(models);
        return Right(updated);
      }

      final newBookmark = QuranBookmarkModel(
        ayahId: ayahId,
        createdAt: createdAt ?? DateTime.now(),
        pageNumber: pageNumber,
        name: name,
        colorCode: colorCode,
      );

      models.add(newBookmark);
      await localDataSource.saveBookmarks(models);
      return Right(newBookmark);
    } catch (e) {
      return Left(CacheFailure(message: 'Failed to add bookmark: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> removeBookmark(AyahId ayahId) async {
    try {
      final models = await localDataSource.getBookmarks();
      final initialLength = models.length;
      models.removeWhere((b) => b.ayahId == ayahId);
      if (models.length != initialLength) {
        await localDataSource.saveBookmarks(models);
      }
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(message: 'Failed to remove bookmark: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> isBookmarked(AyahId ayahId) async {
    try {
      final models = await localDataSource.getBookmarks();
      final exists = models.any((b) => b.ayahId == ayahId);
      return Right(exists);
    } catch (e) {
      return Left(CacheFailure(message: 'Failed to check bookmark status: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> toggleBookmark({
    required AyahId ayahId,
    int? pageNumber,
    String? name,
    int? colorCode,
  }) async {
    try {
      final models = await localDataSource.getBookmarks();
      final existingIndex = models.indexWhere((b) => b.ayahId == ayahId);

      if (existingIndex != -1) {
        // Remove existing bookmark
        models.removeAt(existingIndex);
        await localDataSource.saveBookmarks(models);
        return const Right(false);
      } else {
        // Add new bookmark
        final newBookmark = QuranBookmarkModel(
          ayahId: ayahId,
          createdAt: DateTime.now(),
          pageNumber: pageNumber,
          name: name,
          colorCode: colorCode,
        );
        models.add(newBookmark);
        await localDataSource.saveBookmarks(models);
        return const Right(true);
      }
    } catch (e) {
      return Left(CacheFailure(message: 'Failed to toggle bookmark: $e'));
    }
  }
}
