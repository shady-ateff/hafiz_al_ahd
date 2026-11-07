import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../repositories/quran_bookmark_repository.dart';

class IsAyahBookmarkedUseCase {
  final QuranBookmarkRepository repository;

  IsAyahBookmarkedUseCase(this.repository);

  Future<Either<Failure, bool>> call(AyahId ayahId) {
    return repository.isBookmarked(ayahId);
  }
}

