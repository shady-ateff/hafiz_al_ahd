import 'dart:developer';
import 'dart:async';
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

  static int _scheduleSessionId = 0;

  ScheduleWeeklyPrayersUseCase({
    required this.getPrayerTimesUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.schedulePrayerUseCase,
    required this.getIqamaDelaysUseCase,
    required this.notificationRepository,
    required this.pref,
  });

  Future<void> execute(double lat, double lng, String city) async {
    // 1. إدارة التضارب (Race Conditions)
    final int currentSession = ++_scheduleSessionId;
    log("🚀 Starting scheduling session #$currentSession on Main Thread with Throttling...");

    // 2. قراءة الإعدادات
    final iqamaDelays = await getIqamaDelaysUseCase.execute();
    final adhanVolume = pref.getDouble('adhan_volume') ?? 1.0;
    final isAdhanVibrationEnabled = pref.getBool('isAdhanVibrationEnabled') ?? true;
    final isIqamaEnabled = pref.getBool('isIqamaEnabled') ?? true;
    final isAzkarReminderEnabled = pref.getBool('isAzkarReminderEnabled') ?? true;

    // 3. مسح الإشعارات القديمة
    await notificationRepository.cancelAllAlarms();
    await notificationRepository.cancelActivePrayerNotification();
    log("🧹 Notifications cleared. Scheduling new notifications for the next 5 days...");

    int notificationId = 1;
    for (int i = 0; i < 5; i++) {
      // 4. التأكد من عدم وجود جلسة جديدة بدأت أثناء العمل
      if (_scheduleSessionId != currentSession) {
        log("🛑 Session #$currentSession cancelled because a newer session started.");
        return;
      }

      final date = DateTime.now().add(Duration(days: i));
      
      final result = await getPrayerTimesUseCase(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
      );
      
      await result.fold((_) async {}, (prayerTimes) async {
        log("📅 Fetched prayer times for ${date.toLocal()} - scheduling...");
        
        notificationId = await _schedulePrayersForDay(
          prayerTimes: prayerTimes,
          currentId: notificationId,
          iqamaDelays: iqamaDelays,
          adhanVolume: adhanVolume,
          isAdhanVibrationEnabled: isAdhanVibrationEnabled,
          isIqamaEnabled: isIqamaEnabled,
          isAzkarReminderEnabled: isAzkarReminderEnabled,
        );
      });
      
      // 5. نظام التقطيع (Chunking / Throttling)
      // هذا السطر السحري يحل مشكلتين:
      // - يحرر הـ Dart Main Thread ليرسم الواجهة (يمنع الـ UI Lag)
      // - يمنع اختناق الـ Native Android Thread بكميات هائلة من הـ PendingIntents
      await Future.delayed(const Duration(milliseconds: 150));
    }
    
    if (_scheduleSessionId == currentSession) {
      final newTargetDate = DateTime.now().add(const Duration(days: 5));
      await pref.setString('scheduled_until_date', newTargetDate.toIso8601String());
      log("✅ Scheduling session #$currentSession complete!");
    }
  }

  Future<int> _schedulePrayersForDay({
    required var prayerTimes, 
    required int currentId,
    required Map<String, int> iqamaDelays,
    required double adhanVolume,
    required bool isAdhanVibrationEnabled,
    required bool isIqamaEnabled,
    required bool isAzkarReminderEnabled,
  }) async {
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

      if (prayer.time!.isAfter(DateTime.now())) {
        log("⏲️ Scheduling ALARM for prayer: ${prayer.name} at ${prayer.time}");
        await notificationRepository.scheduleAdhanAlarm(
          id: currentId++,
          title: 'حان الآن موعد صلاة ${prayer.name}',
          body: prayer.name == 'الفجر' ? 'الصلاة خير من النوم' : 'حي على الصلاة، حي على الفلاح',
          scheduledTime: prayer.time!,
          assetAudioPath: prayer.name == 'الفجر' ? 'assets/sounds/fajr_azan.mp3' : 'assets/sounds/adhan.mp3',
          volume: adhanVolume,
          enableVibration: isAdhanVibrationEnabled,
        );
      }

      final int iqamaDelay = iqamaDelays[prayer.key] ?? -1;

      if (isIqamaEnabled && iqamaDelay > 0) {
        final DateTime iqamaTime = prayer.time!.add(Duration(minutes: iqamaDelay));
        if (iqamaTime.isAfter(DateTime.now())) {
          await notificationRepository.schedulePrayerNotification(
            id: currentId++,
            title: 'إقامة صلاة ${prayer.name}',
            body: 'تجهز للصلاة، ستقام الصلاة الآن',
            scheduledTime: iqamaTime,
            soundName: 'iqama_sound',
            payload: 'iqama_${currentId}_${prayer.name}',
          );
        }
      }

      if (isAzkarReminderEnabled) {
        DateTime azkarAfterPrayerTime;
        if (isIqamaEnabled && iqamaDelay > 0) {
          azkarAfterPrayerTime = prayer.time!.add(Duration(minutes: iqamaDelay + 5));
        } else {
          azkarAfterPrayerTime = prayer.time!.add(const Duration(minutes: 25));
        }

        if (azkarAfterPrayerTime.isAfter(DateTime.now())) {
          await notificationRepository.schedulePrayerNotification(
            id: currentId++,
            title: 'أذكار بعد الصلاة',
            body: 'تقبل الله صلاتك، لا تنس أذكار ما بعد صلاة ${prayer.name}.',
            scheduledTime: azkarAfterPrayerTime,
            payload: 'azkar_after_prayer',
          );
        }

        DateTime? specificAzkarTime;
        String? specificAzkarTitle;
        String? specificAzkarBody;
        String? specificAzkarPayload;

        if (prayer.key == 'fajr') {
          specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          specificAzkarTitle = 'أذكار الصباح';
          specificAzkarBody = 'حان وقت أذكار الصباح، احفظ عهدك مع الله.';
          specificAzkarPayload = 'azkar_morning';
        } else if (prayer.key == 'asr') {
          specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          specificAzkarTitle = 'أذكار المساء';
          specificAzkarBody = 'حان وقت أذكار المساء، احفظ عهدك مع الله.';
          specificAzkarPayload = 'azkar_evening';
        }

        if (specificAzkarTime != null && specificAzkarTime.isAfter(DateTime.now())) {
          await notificationRepository.schedulePrayerNotification(
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
