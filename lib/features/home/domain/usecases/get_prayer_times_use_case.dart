import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/faluire.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';

class GetPrayerTimesUseCase {

  final PrayerTimesRepo prayerTimesRepo;
  GetPrayerTimesUseCase(this.prayerTimesRepo);

  Future<Either<Failure, PrayerTimesEntity>> call(
    {
      required double latitude,
      required double longitude,
      required DateTime date,
      String? city,
      String? country,
      String? method,
    }
  ){
    return prayerTimesRepo.getPrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: date,
      city: city,
      country: country,
      method: method,
    );
  }
  
}