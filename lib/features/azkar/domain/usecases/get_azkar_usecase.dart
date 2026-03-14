import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/repositories/azkar_repository.dart';

class GetAzkarUseCase {
  final AzkarRepository repository;

  GetAzkarUseCase(this.repository);

  Future<Either<String, Map<String, List<AzkarItem>>>> call() async {
    return await repository.getAzkarData();
  }
}
