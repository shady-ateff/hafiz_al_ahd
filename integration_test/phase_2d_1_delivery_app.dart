import 'dart:convert';
import 'dart:developer';

import 'package:alarm/alarm.dart';
import 'package:flutter/widgets.dart';

/// Phase 2D.1 Physical Delivery Diagnostic Harness App.
///
/// Runs as a persistent application to eliminate test runner auto-uninstall side effects.
/// Schedules target alarm #999901 for host-side verification.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log('🔧 [Delivery App Harness] Initializing Alarm plugin...');
  await Alarm.init();

  const int testAlarmId = 999901;
  final targetTime = DateTime.now().add(const Duration(seconds: 45));

  log('⏰ [Delivery App Harness] Scheduling alarm #$testAlarmId for ${targetTime.toIso8601String()}...');
  final alarmSettings = AlarmSettings(
    id: testAlarmId,
    dateTime: targetTime,
    assetAudioPath: 'assets/sounds/fajr_azan.mp3',
    loopAudio: true,
    vibrate: true,
    androidFullScreenIntent: true,
    androidStopAlarmOnTermination: false,
    volumeSettings: VolumeSettings.fade(
      volume: 0.5,
      fadeDuration: const Duration(seconds: 2),
      volumeEnforced: false,
    ),
    notificationSettings: const NotificationSettings(
      title: 'أذان الفجر (اختبار ما بعد موت العملية)',
      body: 'الصلاة خير من النوم',
      stopButton: 'إيقاف الأذان',
      icon: 'notification_icon',
    ),
  );

  await Alarm.set(alarmSettings: alarmSettings);

  final record = {
    'event_type': 'TARGET_ALARM_SCHEDULED',
    'id': testAlarmId,
    'scheduled_epoch_ms': targetTime.millisecondsSinceEpoch,
    'scheduled_time_utc': targetTime.toUtc().toIso8601String(),
  };
  // ignore: avoid_print
  print('[PHASE_2D_TARGET_SCHEDULED] ${jsonEncode(record)}');

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}

