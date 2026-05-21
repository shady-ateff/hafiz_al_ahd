import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GetPrayerTimesUseCase {

  final PrayerTimesRepo prayerTimesRepo;
  final SharedPreferences pref;
  GetPrayerTimesUseCase(this.prayerTimesRepo, {required this.pref});

  Future<Either<Failure, PrayerTimesEntity>> call(
    {
      required double latitude,
      required double longitude,
      required DateTime date,
      String? city,
      String? country,
      String? method,
    }
  ) async {
    final result = await prayerTimesRepo.getPrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: date,
      city: city,
      country: country,
      method: method,
    );

    // تطبيق فرق التوقيت الصيفي لو المستخدم فعّله من الإعدادات
    final int dstOffset = pref.getInt('dst_offset_minutes') ?? 0;
    return result.map((entity) => entity.applyDstOffset(dstOffset));
  }
  
}