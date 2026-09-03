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
    final bool isAdhanVibrationEnabled = pref.getBool('isAdhanVibrationEnabled') ?? true; // 👈 الاهتزاز

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
          enableVibration: isAdhanVibrationEnabled, // 👈 تمرير الاهتزاز
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

      // 3. جدولة تذكير الأذكار (بعد الصلاة، الصباح، المساء)
      bool isAzkarReminderEnabled = pref.getBool('isAzkarReminderEnabled') ?? true;
      
      if (isAzkarReminderEnabled) {
        // جدولة أذكار بعد الصلاة لجميع الصلوات دائماً
        DateTime azkarAfterPrayerTime;
        if (isIqamaEnabled && iqamaDelay > 0) {
          azkarAfterPrayerTime = prayer.time!.add(Duration(minutes: iqamaDelay + 5));
        } else {
          azkarAfterPrayerTime = prayer.time!.add(const Duration(minutes: 25));
        }

        if (azkarAfterPrayerTime.isAfter(DateTime.now())) {
          log("📿 Scheduling Azkar (أذكار بعد الصلاة) at $azkarAfterPrayerTime");
          await schedulePrayerUseCase.execute(
            id: currentId++,
            title: 'أذكار بعد الصلاة',
            body: 'تقبل الله صلاتك، لا تنس أذكار ما بعد صلاة ${prayer.name}.',
            scheduledTime: azkarAfterPrayerTime,
            payload: 'azkar_after_prayer',
          );
        }

        // جدولة أذكار الصباح والمساء الخاصة بالفجر والعصر
        DateTime? specificAzkarTime;
        String? specificAzkarTitle;
        String? specificAzkarBody;
        String? specificAzkarPayload;

        if (prayer.key == 'fajr') {
          // أذكار الصباح بعد الفجر بـ 30 دقيقة
          specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          specificAzkarTitle = 'أذكار الصباح';
          specificAzkarBody = 'حان وقت أذكار الصباح، احفظ عهدك مع الله.';
          specificAzkarPayload = 'azkar_morning';
        } else if (prayer.key == 'asr') {
          // أذكار المساء بعد العصر بـ 30 دقيقة
          specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          specificAzkarTitle = 'أذكار المساء';
          specificAzkarBody = 'حان وقت أذكار المساء، احفظ عهدك مع الله.';
          specificAzkarPayload = 'azkar_evening';
        }

        if (specificAzkarTime != null && specificAzkarTime.isAfter(DateTime.now())) {
          log("📿 Scheduling Azkar ($specificAzkarTitle) at $specificAzkarTime");
          await schedulePrayerUseCase.execute(
            id: currentId++,
            title: specificAzkarTitle!,
            body: specificAzkarBody!,
            scheduledTime: specificAzkarTime,
            payload: specificAzkarPayload!,
          );
        }
      }
    }
    return currentId;
  }
}
