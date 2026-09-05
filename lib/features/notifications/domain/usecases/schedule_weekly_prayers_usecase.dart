import 'dart:developer';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:alarm/alarm.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/prayer_times_repo_impl.dart';

class ScheduleWeeklyPrayersUseCase {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  final GetIqamaDelaysUseCase getIqamaDelaysUseCase;
  final BaseNotificationRepository notificationRepository;
  final SharedPreferences pref;

  static Isolate? _activeIsolate;

  ScheduleWeeklyPrayersUseCase({
    required this.getPrayerTimesUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.schedulePrayerUseCase,
    required this.getIqamaDelaysUseCase,
    required this.notificationRepository,
    required this.pref,
  });

  Future<void> execute(double lat, double lng, String city) async {
    if (_activeIsolate != null) {
      _activeIsolate!.kill(priority: Isolate.immediate);
      _activeIsolate = null;
      log("🛑 Killed previous scheduling isolate to avoid race conditions.");
    }

    // قراءة الإعدادات بالكامل من الـ Main Thread
    final iqamaDelays = await getIqamaDelaysUseCase.execute();
    final adhanVolume = pref.getDouble('adhan_volume') ?? 1.0;
    final isAdhanVibrationEnabled = pref.getBool('isAdhanVibrationEnabled') ?? true;
    final isIqamaEnabled = pref.getBool('isIqamaEnabled') ?? true;
    final isAzkarReminderEnabled = pref.getBool('isAzkarReminderEnabled') ?? true;
    final dstOffset = pref.getInt('dst_offset_minutes') ?? 0;

    final token = RootIsolateToken.instance!;
    
    final isolateData = {
      'token': token,
      'lat': lat,
      'lng': lng,
      'city': city,
      'iqamaDelays': iqamaDelays,
      'adhanVolume': adhanVolume,
      'isAdhanVibrationEnabled': isAdhanVibrationEnabled,
      'isIqamaEnabled': isIqamaEnabled,
      'isAzkarReminderEnabled': isAzkarReminderEnabled,
      'dstOffset': dstOffset,
    };

    log("🚀 Spawning background isolate for notification scheduling...");
    _activeIsolate = await Isolate.spawn(_isolateEntryPoint, isolateData);

    final newTargetDate = DateTime.now().add(const Duration(days: 5));
    await pref.setString('scheduled_until_date', newTargetDate.toIso8601String());
  }

  static Future<void> _isolateEntryPoint(Map<String, dynamic> data) async {
    // 1. Initialization in Background Isolate
    BackgroundIsolateBinaryMessenger.ensureInitialized(data['token']);
    DartPluginRegistrant.ensureInitialized();
    await Alarm.init();

    final notifRepo = NotificationRepositoryImpl();
    await notifRepo.initialize();

    final prayerLocalSource = PrayerTimesLocalDataSource();
    final prayerRepo = PrayerTimesRepoImpl(prayerLocalSource);

    // 2. Data extraction
    final lat = data['lat'] as double;
    final lng = data['lng'] as double;
    final city = data['city'] as String;
    final iqamaDelays = data['iqamaDelays'] as Map<String, int>;
    final adhanVolume = data['adhanVolume'] as double;
    final isAdhanVibrationEnabled = data['isAdhanVibrationEnabled'] as bool;
    final isIqamaEnabled = data['isIqamaEnabled'] as bool;
    final isAzkarReminderEnabled = data['isAzkarReminderEnabled'] as bool;
    final dstOffset = data['dstOffset'] as int;

    // 3. Clear old notifications
    await notifRepo.cancelAllAlarms();
    await notifRepo.cancelActivePrayerNotification();
    log("[Isolate] Notifications cleared. Scheduling new notifications for the next 5 days...");

    int notificationId = 1;
    for (int i = 0; i < 5; i++) {
      final date = DateTime.now().add(Duration(days: i));
      
      final result = await prayerRepo.getPrayerTimes(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
      );
      
      await result.fold((_) async {}, (prayerTimesEntity) async {
        final prayerTimes = prayerTimesEntity.applyDstOffset(dstOffset);
        log("[Isolate] Fetched prayer times for ${date.toLocal()} - scheduling...");
        
        notificationId = await _schedulePrayersForDay(
          prayerTimes: prayerTimes,
          currentId: notificationId,
          notifRepo: notifRepo,
          iqamaDelays: iqamaDelays,
          adhanVolume: adhanVolume,
          isAdhanVibrationEnabled: isAdhanVibrationEnabled,
          isIqamaEnabled: isIqamaEnabled,
          isAzkarReminderEnabled: isAzkarReminderEnabled,
        );
      });
      
      // THROTTLING / CHUNKING
      await Future.delayed(const Duration(milliseconds: 150));
    }
    
    log("[Isolate] Scheduling complete! Isolate will now exit.");
  }

  static Future<int> _schedulePrayersForDay({
    required var prayerTimes, 
    required int currentId,
    required NotificationRepositoryImpl notifRepo,
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
        log("[Isolate] ⏲️ Scheduling ALARM for prayer: ${prayer.name} at ${prayer.time} with volume $adhanVolume");
        await notifRepo.scheduleAdhanAlarm(
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
          log("[Isolate] 📅 Scheduling Iqama for ${prayer.name} at $iqamaTime");
          await notifRepo.schedulePrayerNotification(
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
          log("[Isolate] 📿 Scheduling Azkar (أذكار بعد الصلاة) at $azkarAfterPrayerTime");
          await notifRepo.schedulePrayerNotification(
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
          log("[Isolate] 📿 Scheduling Azkar ($specificAzkarTitle) at $specificAzkarTime");
          await notifRepo.schedulePrayerNotification(
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
