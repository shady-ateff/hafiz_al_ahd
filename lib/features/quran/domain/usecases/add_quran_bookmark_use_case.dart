import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../entities/quran_bookmark.dart';
import '../repositories/quran_bookmark_repository.dart';

class AddQuranBookmarkUseCase {
  final QuranBookmarkRepository repository;

  AddQuranBookmarkUseCase(this.repository);

  Future<Either<Failure, QuranBookmark>> call({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  }) {
    return repository.addBookmark(
      ayahId: ayahId,
      pageNumber: pageNumber,
      createdAt: createdAt,
      name: name,
      colorCode: colorCode,
    );
  }
}

