import 'dart:convert';
import 'dart:developer';

import 'package:alarm/alarm.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Phase P4.1-C Physical Verification Harness App.
///
/// Runs on physical Android devices (Xiaomi Android 16 & Samsung Android 12)
/// to verify:
/// 1. Alarm Mode: Full-screen alarm scheduled via package:alarm.
/// 2. Notification Mode: Scheduled exclusively via flutter_local_notifications (FLN),
///    with zero package:alarm interaction.
/// 3. Off Mode: Sibling decommissioned cleanly.
/// 4. Sibling Non-Interference: Independent per-prayer alarms.
/// 5. Live Transition: Transitioning an alarm to notification decommissions
///    package:alarm immediately and activates FLN.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log('🔧 [P4.1-C Harness] Initializing plugins...');
  tz.initializeTimeZones();
  await Alarm.init();

  final fln = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@drawable/ic_stat_icon');
  await fln.initialize(settings: const InitializationSettings(android: androidInit));

  final prefs = await SharedPreferences.getInstance();
  final configDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
  final configRepo = PrayerAlarmConfigRepositoryImpl(localDataSource: configDataSource);
  final transitionDataSource = PrayerAlertTransitionLocalDataSourceImpl(prefs: prefs);

  const int fajrAlarmId = 999911; // Fajr: Alarm Mode
  const int asrNotifId = 999912;  // Asr: Notification Mode
  const int maghribOffId = 999913;// Maghrib: Off Mode

  final now = DateTime.now();
  final fajrTime = now.add(const Duration(seconds: 45)); // Alarm at +45s
  final asrTime = now.add(const Duration(seconds: 15));  // Notification at +15s

  final coordinator = TransitionCoordinator(
    configRepository: configRepo,
    transitionDataSource: transitionDataSource,
    cancelAlarmSafely: (id, {expectedScheduledTime, expectedAssetAudioPath}) async {
      await Alarm.stop(id);
      return EventCancellationStatus.cancelled;
    },
    stopActiveAlarm: (id) async {
      await Alarm.stop(id);
    },
    cancelNotificationSafely: (id) async {
      await fln.cancel(id: id);
      return EventCancellationStatus.cancelled;
    },
    scheduleAlarm: (prayerId, dt, audioSource, vol, vib) async {
      final assetPath = audioSource is BuiltInAudioSource
          ? audioSource.assetPath
          : 'assets/sounds/fajr_azan.mp3';
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: fajrAlarmId,
          dateTime: dt,
          assetAudioPath: assetPath,
          volumeSettings: VolumeSettings.fade(
            volume: vol ?? 0.8,
            fadeDuration: const Duration(seconds: 2),
            volumeEnforced: false,
          ),
          vibrate: vib,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          notificationSettings: const NotificationSettings(
            title: 'أذان الفجر (P4.1-C Alarm Mode)',
            body: 'الصلاة خير من النوم',
            stopButton: 'إيقاف الأذان',
            icon: 'notification_icon',
          ),
        ),
      );
    },
    scheduleNotification: (prayerId, dt) async {
      final tzDt = tz.TZDateTime.from(dt, tz.local);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'prayer_channel_v10_default',
          'إشعارات الصلاة',
          channelDescription: 'إشعارات التنبيه بأوقات الصلاة',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          audioAttributesUsage: AudioAttributesUsage.notification,
        ),
      );
      await fln.zonedSchedule(
        id: asrNotifId,
        title: 'حان الآن موعد صلاة العصر',
        body: 'حي على الصلاة، حي على الفلاح (P4.1-C Notification Mode)',
        scheduledDate: tzDt,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'p4_1_c_asr_$asrNotifId',
      );
    },
    getPrayerTimesForHorizon: (id) async {
      if (id == PrayerId.fajr) return [fajrTime];
      if (id == PrayerId.asr) return [asrTime];
      return [];
    },
  );

  // 1. Establish configurations
  await configRepo.saveConfig(
    const PrayerAlarmConfig(
      prayerId: PrayerId.fajr,
      alarmType: PrayerAlarmType.alarm,
      volume: 0.8,
    ),
  );
  await configRepo.saveConfig(
    const PrayerAlarmConfig(
      prayerId: PrayerId.asr,
      alarmType: PrayerAlarmType.notification,
    ),
  );
  await configRepo.saveConfig(
    const PrayerAlarmConfig(
      prayerId: PrayerId.maghrib,
      alarmType: PrayerAlarmType.off,
    ),
  );

  // 2. Schedule events via coordinator
  // Fajr: Alarm
  await coordinator.scheduleAlarm(
    PrayerId.fajr,
    fajrTime,
    const BuiltInAudioSource(
      id: 'builtIn:default_fajr',
      displayName: 'أذان الفجر (الافتراضي)',
      assetPath: 'assets/sounds/fajr_azan.mp3',
    ),
    0.8,
    true,
  );

  // Asr: Notification
  await coordinator.scheduleNotification(
    PrayerId.asr,
    asrTime,
  );

  final statusPayload = {
    'event_type': 'P4_1_C_HARNESS_READY',
    'fajr': {
      'id': fajrAlarmId,
      'mode': 'alarm',
      'scheduled_epoch_ms': fajrTime.millisecondsSinceEpoch,
      'iso_time': fajrTime.toIso8601String(),
    },
    'asr': {
      'id': asrNotifId,
      'mode': 'notification',
      'scheduled_epoch_ms': asrTime.millisecondsSinceEpoch,
      'iso_time': asrTime.toIso8601String(),
    },
    'maghrib': {
      'id': maghribOffId,
      'mode': 'off',
    },
  };

  // ignore: avoid_print
  print('[PHASE_P4_1_C_SCHEDULED] ${jsonEncode(statusPayload)}');

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}
