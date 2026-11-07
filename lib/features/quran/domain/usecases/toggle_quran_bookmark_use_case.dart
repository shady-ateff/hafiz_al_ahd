import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../repositories/quran_bookmark_repository.dart';

class ToggleQuranBookmarkUseCase {
  final QuranBookmarkRepository repository;

  ToggleQuranBookmarkUseCase(this.repository);

  Future<Either<Failure, bool>> call({
    required AyahId ayahId,
    int? pageNumber,
    String? name,
    int? colorCode,
  }) {
    return repository.toggleBookmark(
      ayahId: ayahId,
      pageNumber: pageNumber,
      name: name,
      colorCode: colorCode,
    );
  }
}
