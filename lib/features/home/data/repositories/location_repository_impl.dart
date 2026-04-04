import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/exception.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';

import '../../domain/entities/location_entity.dart';
import '../../domain/repositories/base_location_repository.dart';
import '../datasources/location_local_data_source.dart';
import '../models/location_model.dart';

class LocationRepositoryImpl implements BaseLocationRepository {
  final BaseLocationLocalDataSource localDataSource;

  LocationRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, void>> saveLocation(LocationEntity location) async {
    try {
      // بنحول الـ Entity لـ Model عشان الـ DataSource يقبله
      final locationModel = LocationModel(
        latitude: location.latitude,
        longitude: location.longitude,
        city: location.city,
        country: location.country,
      );

      await localDataSource.cacheLocation(locationModel);
      return const Right(null); // نجاح، مفيش داتا بترجع
    } on CacheException {
      return Left(
        CacheFailure(message: "فشل في حفظ الموقع. حاول مرة أخرى."),
      ); // فشل، بنرجع Failure مع رسالة
    }
  }

  @override
  Future<Either<Failure, LocationEntity>> getCachedLocation() async {
    try {
      final locationModel = await localDataSource.getCachedLocation();
      return Right(locationModel); // نجاح، بنرجع الداتا
    } on CacheException {
      // الـ Exception اللي اترمى من الـ DataSource اتمسك هنا واتحول لـ Failure محترم
      return Left(CacheFailure(message: "لا يوجد موقع محفوظ مسبقاً."));
    }
  }
}
