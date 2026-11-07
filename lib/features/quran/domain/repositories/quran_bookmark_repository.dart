import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../entities/quran_bookmark.dart';

abstract class QuranBookmarkRepository {
  /// Retrieves all saved bookmarks ordered stably (newest created first).
  Future<Either<Failure, List<QuranBookmark>>> getBookmarks();

  /// Adds or updates a bookmark for the given [ayahId] with optional [name] and [colorCode].
  /// Prevents duplicates: if already bookmarked, updates metadata safely.
  Future<Either<Failure, QuranBookmark>> addBookmark({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  });

  /// Removes a bookmark for the given [ayahId].
  Future<Either<Failure, void>> removeBookmark(AyahId ayahId);

  /// Checks whether the given [ayahId] is currently bookmarked.
  Future<Either<Failure, bool>> isBookmarked(AyahId ayahId);

  /// Toggles the bookmark state: adds if absent, removes if present.
  /// Returns `true` if added, `false` if removed.
  Future<Either<Failure, bool>> toggleBookmark({
    required AyahId ayahId,
    int? pageNumber,
    String? name,
    int? colorCode,
  });
}
