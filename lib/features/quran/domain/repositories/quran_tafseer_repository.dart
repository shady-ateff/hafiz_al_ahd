import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../entities/quran_tafseer.dart';

/// Contract for the Quran Tafseer repository.
/// Exposes operations to retrieve authoritative Tafseer commentary for any Quranic Ayah.
abstract class QuranTafseerRepository {
  /// Retrieves the Tafseer commentary entity for the specified [ayahId].
  ///
  /// Returns:
  /// - [Right(QuranTafseer)] on successful retrieval and parsing.
  /// - [Left(CacheFailure)] if the Ayah is missing, unreadable, or corrupted.
  Future<Either<Failure, QuranTafseer>> getTafseer(AyahId ayahId);
}

