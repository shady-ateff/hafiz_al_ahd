import 'package:flutter/services.dart';
import 'dart:developer';

class NativeAlarmService {
  static const MethodChannel _channel = MethodChannel('com.shadyatef.hafiz_alahd/alarm_channel');

  /// Schedules an Exact Alarm in Native Android bypassing Doze mode.
  /// [triggerTimeMillis] is the exact moment this alarm fires.
  /// The rest of the parameters contain the *Next Next* prayer details to be updated instantly automatically.
  static Future<bool> scheduleNativeSyncAlarm({
    required int triggerTimeMillis, 
    required int notificationId,
    required String notificationTitle,
    required String notificationBody,
    required String nextPrayerName,
    required String nextPrayerTime,
    required int nextPrayerMillis,
    required String fajrTime,
    required String dhuhrTime,
    required String asrTime,
    required String maghribTime,
    required String ishaTime,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>('scheduleExactAlarm', {
        'triggerTime': triggerTimeMillis,
        'notification_id': notificationId,
        'notification_title': notificationTitle,
        'notification_body': notificationBody,
        'next_prayer_name': nextPrayerName,
        'next_prayer_time': nextPrayerTime,
        'next_prayer_millis': nextPrayerMillis,
        'fajr_time': fajrTime,
        'dhuhr_time': dhuhrTime,
        'asr_time': asrTime,
        'maghrib_time': maghribTime,
        'isha_time': ishaTime,
      });
      return success ?? false;
    } catch (e) {
      log("Error scheduling native sync alarm: $e");
      return false;
    }
  }
}
