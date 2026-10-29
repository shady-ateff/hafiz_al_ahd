import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';

abstract class PrayerTimesRepo {
  Future<Either<Failure, PrayerTimesEntity>> getPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
    String? madhab,
    double? customFajrAngle,
    double? customIshaAngle,
  });
}
