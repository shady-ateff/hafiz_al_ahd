import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/repositories/azkar_repository.dart';
import 'package:hafiz_al_ahd/features/azkar/data/datasources/azkar_local_data_source.dart';

class AzkarRepositoryImpl implements AzkarRepository {
  final AzkarLocalDataSource localDataSource;

  AzkarRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<String, Map<String, List<AzkarItem>>>> getAzkarData() async {
    try {
      final localAzkar = await localDataSource.getAzkar();
      return Right(localAzkar);
    } catch (e) {
      return Left('حدث خطأ أثناء تحميل الأذكار');
    }
  }
}
