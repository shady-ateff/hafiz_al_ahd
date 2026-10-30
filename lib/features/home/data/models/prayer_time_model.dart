import 'package:adhan_dart/adhan_dart.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';

class PrayerTimesModel extends PrayerTimesEntity {
  PrayerTimesModel({
    required super.fajr,
    required super.sunrise,
    required super.dhuhr,
    required super.asr,
    required super.maghrib,
    required super.isha,
    super.tomorrowFajr,
  });

  factory PrayerTimesModel.fromAdhanObject(PrayerTimes obj, [DateTime? tomorrowFajr]) {
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
