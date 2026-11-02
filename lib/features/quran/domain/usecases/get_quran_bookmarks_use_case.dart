import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/quran_bookmark.dart';
import '../repositories/quran_bookmark_repository.dart';

class GetQuranBookmarksUseCase {
  final QuranBookmarkRepository repository;

  GetQuranBookmarksUseCase(this.repository);

  Future<Either<Failure, List<QuranBookmark>>> call() {
    return repository.getBookmarks();
  }
}

