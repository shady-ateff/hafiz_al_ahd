import 'package:hafiz_al_ahd/features/home/domain/entities/next_pray_time.dart';

class PrayerTimesEntity {
  DateTime? fajr; //date time easier in count down
  DateTime? sunrise;
  DateTime? dhuhr;
  DateTime? asr;
  DateTime? maghrib;
  DateTime? isha;
  PrayerTimesEntity({
    this.fajr,
    this.sunrise,
    this.dhuhr,
    this.asr,
    this.maghrib,
    this.isha,
  });
  // دالة ذكية لمعرفة الصلاة القادمة والوقت المتبقي لها
  // بترجع Record فيه: اسم الصلاة، وقتها، والوقت المتبقي
  NextPrayerTime getNextPrayer(DateTime currentTime) {
    // 1. بنرتب الصلوات في مصفوفة بالترتيب الزمني
    final prayers = [
      (name: 'الفجر', time: fajr),
      (name: 'الشروق', time: sunrise),
      (name: 'الظهر', time: dhuhr),
      (name: 'العصر', time: asr),
      (name: 'المغرب', time: maghrib),
      (name: 'العشاء', time: isha),
    ];


    // 2. بنمشي عليهم صلاة صلاة، أول صلاة وقتها لسه مجاش (isAfter) تبقى هي دي!
    for (var prayer in prayers) {
      DateTime iqamaTime = prayer.time!.add(Duration(minutes: _getIqamaMinutes(prayer.name)));
      if (prayer.time!.isAfter(currentTime)) {
        return NextPrayerTime(
          name: prayer.name,
          time: prayer.time,
          remaining: prayer.time!.difference(currentTime),
          isNextPrayer: true,
          isIqama: false,
        );
      } else if (currentTime.isBefore(iqamaTime) &&
          _getIqamaMinutes(prayer.name) > 0) {
        // لو الوقت الحالي هو بالظبط وقت الصلاة أو بعده بقليل، نعتبرها الصلاة القادمة
        return NextPrayerTime(
          name: prayer.name,
          time: iqamaTime,
          remaining: iqamaTime.difference(currentTime), // الصلاة جايه دلوقتي
          isNextPrayer: true,
          isIqama: true,
        );
      }
    }

    // 3. الفخ: لو اللوب خلص ومفيش صلاة، معناه إننا بعد العشاء
    // إذن الصلاة القادمة هي "فجر اليوم التالي"
    final nextFajr = fajr?.add(const Duration(days: 1));
    return NextPrayerTime(
      name: 'الفجر',
      time: nextFajr,
      remaining: nextFajr?.difference(currentTime) ?? Duration.zero,
      isNextPrayer: true,
      isIqama: false,
    );
  }

  int _getIqamaMinutes(String prayerName) {
    if (prayerName == 'المغرب') return 15;
    if (prayerName == 'الشروق') return 0; // مفيش إقامة للشروق
    return 20; // الفجر، الظهر، العصر، العشاء
  }
}
