import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/faluire.dart';
import '../entities/location_entity.dart';
import '../repositories/base_location_repository.dart';

class SaveLocationUseCase {
  final BaseLocationRepository repository;

  SaveLocationUseCase(this.repository);

  Future<Either<Failure, void>> call(LocationEntity location) async {
    return await repository.saveLocation(location);
  }
}