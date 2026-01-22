class PrayerTimesEntity {
  DateTime? fajr;   //date time easier in count down
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
}