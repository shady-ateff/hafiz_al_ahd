import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';

sealed class PrayerTimesStates {}

class PrayerTimesInitial extends PrayerTimesStates {}
class PrayerTimesLoading extends PrayerTimesStates {}
class PrayerTimesLoaded extends PrayerTimesStates {
  final PrayerTimesEntity prayerTimes;
  PrayerTimesLoaded(this.prayerTimes);
}
class PrayerTimesError extends PrayerTimesStates {
  final String message;
  PrayerTimesError(this.message);
}