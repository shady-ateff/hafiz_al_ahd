import 'package:dartz/dartz.dart';
import '../../../../core/errors/exception.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_tafseer.dart';
import '../../domain/repositories/quran_tafseer_repository.dart';
import '../datasources/quran_tafseer_local_data_source.dart';
import '../datasources/tafseer_text_parser.dart';

/// Implementation of [QuranTafseerRepository] that retrieves Tafseer commentary
/// from [BaseQuranTafseerLocalDataSource] and parses embedded Quranic quotes into typed segments.
class QuranTafseerRepositoryImpl implements QuranTafseerRepository {
  final BaseQuranTafseerLocalDataSource localDataSource;

  QuranTafseerRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, QuranTafseer>> getTafseer(AyahId ayahId) async {
    try {
      final rawText = await localDataSource.getTafseerText(ayahId);
      final segments = TafseerTextParser.parse(rawText);

      final tafseer = QuranTafseer(
        ayahId: ayahId,
        rawText: rawText,
        segments: segments,
      );

      return Right(tafseer);
    } on CacheException {
      return Left(CacheFailure(
        message: 'Tafseer not found for Ayah ${ayahId.formatted}',
      ));
    } catch (e) {
      return Left(CacheFailure(
        message: 'Failed to retrieve Tafseer for Ayah ${ayahId.formatted}: $e',
      ));
    }
  }
}

