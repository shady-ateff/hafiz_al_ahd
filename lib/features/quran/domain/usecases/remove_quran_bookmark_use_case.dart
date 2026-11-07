import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../repositories/quran_bookmark_repository.dart';

class RemoveQuranBookmarkUseCase {
  final QuranBookmarkRepository repository;

  RemoveQuranBookmarkUseCase(this.repository);

  Future<Either<Failure, void>> call(AyahId ayahId) {
    return repository.removeBookmark(ayahId);
  }
}

