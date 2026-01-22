import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/faluire.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';

abstract class PrayerTimesRepo {
  Future<Either<Failure, PrayerTimesEntity>> getPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method, //UMM Al-Qura or Egyptian General

    //parameters
    //* Get prayer times for a specific date and location */
  });
}
