import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../entities/location_entity.dart';

abstract class BaseLocationRepository {
  // دالة الحفظ (بترجع void لو نجحت، أو Failure لو فشلت)
  Future<Either<Failure, void>> saveLocation(LocationEntity location);

  // دالة الاسترجاع (بترجع Entity لو نجحت، أو Failure لو الكاش فاضي)
  Future<Either<Failure, LocationEntity>> getCachedLocation();
}
