import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/faluire.dart';
import '../entities/location_entity.dart';
import '../repositories/base_location_repository.dart';

class GetCachedLocationUseCase {
  final BaseLocationRepository repository;

  GetCachedLocationUseCase(this.repository);

  Future<Either<Failure, LocationEntity>> call() async {
    return await repository.getCachedLocation();
  }
}