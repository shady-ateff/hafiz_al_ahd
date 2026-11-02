import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../entities/quran_tafseer.dart';
import '../repositories/quran_tafseer_repository.dart';

/// Use case to fetch the Tafseer commentary for a specific Quranic Ayah.
class GetQuranTafseerUseCase {
  final QuranTafseerRepository repository;

  GetQuranTafseerUseCase(this.repository);

  /// Executes the use case for the given [ayahId].
  Future<Either<Failure, QuranTafseer>> call(AyahId ayahId) {
    return repository.getTafseer(ayahId);
  }
}

