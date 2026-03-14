import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';

abstract class AzkarRepository {
  Future<Either<String, Map<String, List<AzkarItem>>>> getAzkarData();
}
