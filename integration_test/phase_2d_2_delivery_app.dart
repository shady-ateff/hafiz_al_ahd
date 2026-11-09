import 'dart:convert';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Phase 2D.2 Notification Delivery Harness Application.
///
/// Runs as a standalone test harness to schedule target prayer notifications
/// for host-side native Android OS verification (AlarmManager & NotificationManager).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log('🔧 [Notification Harness] Initializing timezone data...');
  tz.initializeTimeZones();

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid = AndroidInitializationSettings('@drawable/ic_stat_icon');
  const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  const int targetId = int.fromEnvironment('TARGET_ID', defaultValue: 999902);
  const int horizonSeconds = int.fromEnvironment('HORIZON_SEC', defaultValue: 15);
  const String channelId = String.fromEnvironment('CHANNEL_ID', defaultValue: 'prayer_channel_v10_default');
  const bool scheduleSecondary = bool.fromEnvironment('SCHEDULE_SECONDARY', defaultValue: false);
  const int secondaryId = int.fromEnvironment('SECONDARY_ID', defaultValue: 999903);
  const int secondaryHorizonSeconds = int.fromEnvironment('SECONDARY_HORIZON_SEC', defaultValue: 30);
  const int cleanupDelaySeconds = int.fromEnvironment('CLEANUP_DELAY_SEC', defaultValue: 0);
  const int teardownDelaySeconds = int.fromEnvironment('TEARDOWN_DELAY_SEC', defaultValue: 0);

  final now = DateTime.now();
  final targetTime = now.add(Duration(seconds: horizonSeconds));
  final tzTargetTime = tz.TZDateTime.from(targetTime, tz.local);
  final runMarker = 'marker_${targetTime.millisecondsSinceEpoch}_$targetId';
  final targetTitle = '[PHASE_2D_2_TEST_${targetTime.millisecondsSinceEpoch}] صلاة الفجر';
  final targetBody = 'حان الآن موعد صلاة الفجر (Target #$targetId marker:$runMarker)';

  const androidDetails = AndroidNotificationDetails(
    channelId,
    'إشعارات الصلاة',
    channelDescription: 'إشعارات التنبيه بأوقات الصلاة والإقامة',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
  );
  const notificationDetails = NotificationDetails(android: androidDetails);

  log('⏰ [Notification Harness] Scheduling target notification #$targetId for ${targetTime.toIso8601String()}...');
  await flutterLocalNotificationsPlugin.zonedSchedule(
    id: targetId,
    title: targetTitle,
    body: targetBody,
    scheduledDate: tzTargetTime,
    notificationDetails: notificationDetails,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: runMarker,
  );

  Map<String, dynamic>? secondaryRecord;
  if (scheduleSecondary) {
    final secondaryTime = now.add(Duration(seconds: secondaryHorizonSeconds));
    final tzSecondaryTime = tz.TZDateTime.from(secondaryTime, tz.local);
    final secondaryMarker = 'marker_${secondaryTime.millisecondsSinceEpoch}_$secondaryId';
    final secondaryTitle = '[PHASE_2D_2_TEST_${secondaryTime.millisecondsSinceEpoch}] صلاة الظهر';
    final secondaryBody = 'حان الآن موعد صلاة الظهر (Secondary #$secondaryId marker:$secondaryMarker)';

    log('⏰ [Notification Harness] Scheduling secondary notification #$secondaryId for ${secondaryTime.toIso8601String()}...');
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: secondaryId,
      title: secondaryTitle,
      body: secondaryBody,
      scheduledDate: tzSecondaryTime,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: secondaryMarker,
    );

    secondaryRecord = {
      'id': secondaryId,
      'scheduled_epoch_ms': secondaryTime.millisecondsSinceEpoch,
      'scheduled_time_iso': secondaryTime.toIso8601String(),
      'run_marker': secondaryMarker,
      'title': secondaryTitle,
    };
  }

  final pendingRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  final targetPendingFound = pendingRequests.any((r) => r.id == targetId);
  final secondaryPendingFound = scheduleSecondary ? pendingRequests.any((r) => r.id == secondaryId) : null;

  final eventData = {
    'event_type': 'TARGET_NOTIFICATION_SCHEDULED',
    'target_id': targetId,
    'scheduled_epoch_ms': targetTime.millisecondsSinceEpoch,
    'scheduled_time_iso': targetTime.toIso8601String(),
    'channel_id': channelId,
    'run_marker': runMarker,
    'title': targetTitle,
    'body': targetBody,
    'pending_plugin_count': pendingRequests.length,
    'target_pending_found': targetPendingFound,
    'secondary_scheduled': scheduleSecondary,
    'secondary_details': secondaryRecord,
    'secondary_pending_found': secondaryPendingFound,
  };

  // ignore: avoid_print
  print('[PHASE_2D_NOTIF_SCHEDULED] ${jsonEncode(eventData)}');

  if (cleanupDelaySeconds > 0) {
    Future.delayed(Duration(seconds: cleanupDelaySeconds), () async {
      log('🧹 [Delivery Harness] Performing surgical cancellation of target #$targetId...');
      await flutterLocalNotificationsPlugin.cancel(id: targetId);

      final activeNotifications = await flutterLocalNotificationsPlugin.getActiveNotifications();
      final pendingRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();

      final record = {
        'action': 'NOTIFICATION_SURGICAL_CLEANUP_COMPLETED',
        'target_id': targetId,
        'secondary_id': secondaryId,
        'target_active_absent': !activeNotifications.any((n) => n.id == targetId),
        'target_pending_absent': !pendingRequests.any((p) => p.id == targetId),
        'secondary_active_present': activeNotifications.any((n) => n.id == secondaryId),
        'secondary_pending_present': pendingRequests.any((p) => p.id == secondaryId),
        'remaining_active_count': activeNotifications.length,
        'remaining_pending_count': pendingRequests.length,
        'remaining_active_ids': activeNotifications.map((n) => n.id).toList(),
        'remaining_pending_ids': pendingRequests.map((p) => p.id).toList(),
      };
      // ignore: avoid_print
      print('[PHASE_2D_NOTIF_CLEANUP_COMPLETED] ${jsonEncode(record)}');
    });
  }

  if (teardownDelaySeconds > 0) {
    Future.delayed(Duration(seconds: teardownDelaySeconds), () async {
      log('🧹 [Delivery Harness] Performing complete teardown of sibling #$secondaryId...');
      if (scheduleSecondary) {
        await flutterLocalNotificationsPlugin.cancel(id: secondaryId);
      }
      // ignore: avoid_print
      print('[PHASE_2D_NOTIF_TEARDOWN_COMPLETED] {"action": "TEARDOWN_COMPLETED"}');
    });
  }

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}
