import 'dart:developer';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleWeeklyPrayersUseCase {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  final GetIqamaDelaysUseCase getIqamaDelaysUseCase;
  final BaseNotificationRepository notificationRepository;
  final SharedPreferences pref;

  ScheduleWeeklyPrayersUseCase({
    required this.getPrayerTimesUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.schedulePrayerUseCase,
    required this.getIqamaDelaysUseCase,
    required this.notificationRepository,
    required this.pref,
  });

  Future<void> execute(double lat, double lng, String city) async {
    await cancelAllNotificationsUseCase.execute();
    log(
      "Notifications cleared. Scheduling new notifications for the next 5 days......",
    );

    int notificationId = 1; // Alarm package requires ID > 0

    for (int i = 0; i < 5; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final result = await getPrayerTimesUseCase(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
      );

      log(
        "Fetched prayer times for ${date.toLocal()} - scheduling notifications...",
      );

      await result.fold((_) async {}, (prayerTimes) async {
        notificationId = await _schedulePrayersForDay(
          prayerTimes,
          notificationId,
        );
      });
    }

    // بعد ما نخلص، نسجل في الكاش إننا أمنّا الـ 5 أيام الجايين
    final newTargetDate = DateTime.now().add(const Duration(days: 5));
    await pref.setString(
      'scheduled_until_date',
      newTargetDate.toIso8601String(),
    );
  }

  Future<int> _schedulePrayersForDay(var prayerTimes, int currentId) async {
    final Map<String, int> iqamaDelays = await getIqamaDelaysUseCase.execute();
    final double adhanVolume = pref.getDouble('adhan_volume') ?? 1.0; // 👈 سحبنا مستوى الصوت

    final prayers = [
      (name: 'الفجر', time: prayerTimes.fajr, key: 'fajr'),
      (name: 'الشروق', time: prayerTimes.sunrise, key: 'shurooq'),
      (name: 'الظهر', time: prayerTimes.dhuhr, key: 'dhuhr'),
      (name: 'العصر', time: prayerTimes.asr, key: 'asr'),
      (name: 'المغرب', time: prayerTimes.maghrib, key: 'maghrib'),
      (name: 'العشاء', time: prayerTimes.isha, key: 'isha'),
    ];

    for (var prayer in prayers) {
      if (prayer.time == null || prayer.key == 'shurooq') continue;

      // 1. جدولة الأذان لو الوقت لسه مجاش
      //    👈 الأذان بيستخدم باكيدج alarm (صوت محمي، foreground service)
      if (prayer.time!.isAfter(DateTime.now())) {
        log(
          "⏲️ Scheduling ALARM for prayer: ${prayer.name} at ${prayer.time} with volume $adhanVolume",
        );

        await notificationRepository.scheduleAdhanAlarm(
          id: currentId++,
          title: 'حان الآن موعد صلاة ${prayer.name}',
          body: prayer.name == 'الفجر'
              ? 'الصلاة خير من النوم'
              : 'حي على الصلاة، حي على الفلاح',
          scheduledTime: prayer.time!,
          assetAudioPath: prayer.name == 'الفجر'
              ? 'assets/sounds/fajr_azan.mp3'
              : 'assets/sounds/adhan.mp3',
          volume: adhanVolume, // 👈 تمرير الصوت هنا
        );
      }

      // 2. جدولة الإقامة في شرط منفصل
      //    👈 الإقامة لسه بتستخدم الإشعارات العادية (صوت قصير مش محتاج حماية)
      final bool isIqamaEnabled = pref.getBool('isIqamaEnabled') ?? true;
      final int iqamaDelay = iqamaDelays[prayer.key] ?? -1;

      if (isIqamaEnabled && iqamaDelay > 0) {
        final DateTime iqamaTime = prayer.time!.add(
          Duration(minutes: iqamaDelay),
        );

        if (iqamaTime.isAfter(DateTime.now())) {
          log("📅 Scheduling Iqama for ${prayer.name} at $iqamaTime");

          await schedulePrayerUseCase.execute(
            id: currentId++,
            title: 'إقامة صلاة ${prayer.name}',
            body: 'تجهز للصلاة، ستقام الصلاة الآن',
            scheduledTime: iqamaTime,
            soundName: 'iqama_sound',
          );
        }
      }
    }
    return currentId;
  }
}
