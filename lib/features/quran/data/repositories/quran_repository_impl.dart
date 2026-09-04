import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../../domain/entities/quran_page.dart';
import '../../domain/repositories/base_quran_repository.dart';
import '../datasources/quran_local_data_source.dart';

class QuranRepositoryImpl implements BaseQuranRepository {
  final BaseQuranLocalDataSource localDataSource;

  QuranRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber) async {
    try {
      // Ensure database is initialized before getting pages
      await localDataSource.initDatabase();
      final quranPage = await localDataSource.getPage(pageNumber);
      return Right(quranPage);
    } catch (e) {
      return Left(CacheFailure(message: e.toString()));
    }
  }
}
