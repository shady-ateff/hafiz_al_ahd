import 'package:adhan/adhan.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';

class PrayerTimesModel extends PrayerTimesEntity {
  PrayerTimesModel({
    required super.fajr,
    required super.sunrise,
    required super.dhuhr,
    required super.asr,
    required super.maghrib,
    required super.isha,
  });

  factory PrayerTimesModel.fromAdhanObject(PrayerTimes obj) {
    return PrayerTimesModel(
      fajr: obj.fajr,
      sunrise: obj.sunrise,
      dhuhr: obj.dhuhr,
      asr: obj.asr,
      maghrib: obj.maghrib,
      isha: obj.isha,
    );
  }
}
