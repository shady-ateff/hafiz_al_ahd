import 'package:hafiz_al_ahd/features/home/domain/entities/next_pray_time.dart';

class PrayerTimesEntity {
  DateTime? fajr; //date time easier in count down
  DateTime? sunrise;
  DateTime? dhuhr;
  DateTime? asr;
  DateTime? maghrib;
  DateTime? isha;
  DateTime? tomorrowFajr; // فجر الغد المحسوب فلكياً وفق تواريخ وتوقيت اليوم التالي بدقة

  PrayerTimesEntity({
    this.fajr,
    this.sunrise,
    this.dhuhr,
    this.asr,
    this.maghrib,
    this.isha,
    this.tomorrowFajr,
  });

  /// تطبيق فرق التوقيت الصيفي (DST) على كل المواقيت.
  /// بترجع Entity جديدة بالأوقات المُعدّلة، من غير ما تمس الأصلية.
  PrayerTimesEntity applyDstOffset(int offsetMinutes) {
    if (offsetMinutes == 0) return this;
    final offset = Duration(minutes: offsetMinutes);
    return PrayerTimesEntity(
      fajr: fajr?.add(offset),
      sunrise: sunrise?.add(offset),
      dhuhr: dhuhr?.add(offset),
      asr: asr?.add(offset),
      maghrib: maghrib?.add(offset),
      isha: isha?.add(offset),
      tomorrowFajr: tomorrowFajr?.add(offset),
    );
  }

  /// تطبيق إزاحة مخصصة بالدقائق على كل صلاة على حدة.
  PrayerTimesEntity applyOffsets({
    int fajr = 0,
    int sunrise = 0,
    int dhuhr = 0,
    int asr = 0,
    int maghrib = 0,
    int isha = 0,
  }) {
    if (fajr == 0 &&
        sunrise == 0 &&
        dhuhr == 0 &&
        asr == 0 &&
        maghrib == 0 &&
        isha == 0) {
      return this;
    }
    return PrayerTimesEntity(
      fajr: this.fajr?.add(Duration(minutes: fajr)),
      sunrise: this.sunrise?.add(Duration(minutes: sunrise)),
      dhuhr: this.dhuhr?.add(Duration(minutes: dhuhr)),
      asr: this.asr?.add(Duration(minutes: asr)),
      maghrib: this.maghrib?.add(Duration(minutes: maghrib)),
      isha: this.isha?.add(Duration(minutes: isha)),
      tomorrowFajr: this.tomorrowFajr?.add(Duration(minutes: fajr)),
    );
  }

  // دالة ذكية لمعرفة الصلاة القادمة والوقت المتبقي لها
  // بترجع Record فيه: اسم الصلاة، وقتها، والوقت المتبقي
  NextPrayerTime getNextPrayer(
    DateTime currentTime, {
    Map<String, int>? iqamaDelays,
  }) {
    // 1. بنرتب الصلوات في مصفوفة بالترتيب الزمني
    final prayers = [
      (name: 'الفجر', time: fajr, key: 'fajr'),
      (name: 'الشروق', time: sunrise, key: 'shurooq'),
      (name: 'الظهر', time: dhuhr, key: 'dhuhr'),
      (name: 'العصر', time: asr, key: 'asr'),
      (name: 'المغرب', time: maghrib, key: 'maghrib'),
      (name: 'العشاء', time: isha, key: 'isha'),
    ];

    // 2. بنمشي عليهم صلاة صلاة، أول صلاة وقتها لسه مجاش (isAfter) تبقى هي دي!
    for (var prayer in prayers) {
      int delay = _getIqamaMinutes(prayer.name, prayer.key, iqamaDelays);
      DateTime iqamaTime = prayer.time!.add(Duration(minutes: delay));

      if (prayer.time!.isAfter(currentTime)) {
        return NextPrayerTime(
          name: prayer.name,
          time: prayer.time,
          remaining: prayer.time!.difference(currentTime),
          isNextPrayer: true,
          isIqama: false,
        );
      } else if (currentTime.isBefore(iqamaTime) && delay > 0) {
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

    // 3. لو اللوب خلص ومفيش صلاة، معناه إننا بعد العشاء
    // إذن الصلاة القادمة هي "فجر اليوم التالي" المحسوب فلكياً بدقة لتاريخ الغد
    final nextFajr = tomorrowFajr ?? fajr?.add(const Duration(days: 1));
    return NextPrayerTime(
      name: 'الفجر',
      time: nextFajr,
      remaining: nextFajr?.difference(currentTime) ?? Duration.zero,
      isNextPrayer: true,
      isIqama: false,
    );
  }

  int _getIqamaMinutes(
    String prayerName,
    String prayerKey,
    Map<String, int>? delays,
  ) {
    if (prayerKey == 'shurooq') return 0; // مفيش إقامة للشروق

    // لو فيه إعدادات جاية من المحفوظات، استخدمها
    if (delays != null && delays.containsKey(prayerKey)) {
      return delays[prayerKey]!;
    }

    // القيم الافتراضية لو مفيش إعدادات
    if (prayerKey == 'maghrib') return 15;
    return 20;
  }
}
