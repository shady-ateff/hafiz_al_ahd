import 'dart:convert';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Phase 2D.2 Notification Delivery Surgical Cleanup Application.
///
/// Cancels target notification #999902 (and optionally #999903) without blanket wipes.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log('🔧 [Notification Cleanup Harness] Initializing plugin...');

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid = AndroidInitializationSettings('@drawable/ic_stat_icon');
  const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  const int targetId = int.fromEnvironment('TARGET_ID', defaultValue: 999902);
  const int secondaryId = int.fromEnvironment('SECONDARY_ID', defaultValue: 999903);
  const bool cleanSecondary = bool.fromEnvironment('CLEAN_SECONDARY', defaultValue: false);

  log('🧹 [Notification Cleanup Harness] Canceling target notification #$targetId...');
  await flutterLocalNotificationsPlugin.cancel(id: targetId);

  if (cleanSecondary) {
    log('🧹 [Notification Cleanup Harness] Canceling secondary notification #$secondaryId...');
    await flutterLocalNotificationsPlugin.cancel(id: secondaryId);
  }

  final activeNotifications = await flutterLocalNotificationsPlugin.getActiveNotifications();
  final pendingRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();

  final targetActiveAbsent = !activeNotifications.any((n) => n.id == targetId);
  final targetPendingAbsent = !pendingRequests.any((p) => p.id == targetId);

  final secondaryActivePresent = activeNotifications.any((n) => n.id == secondaryId);
  final secondaryPendingPresent = pendingRequests.any((p) => p.id == secondaryId);

  final record = {
    'action': 'NOTIFICATION_SURGICAL_CLEANUP_COMPLETED',
    'target_id': targetId,
    'clean_secondary': cleanSecondary,
    'secondary_id': secondaryId,
    'target_active_absent': targetActiveAbsent,
    'target_pending_absent': targetPendingAbsent,
    'secondary_active_present': secondaryActivePresent,
    'secondary_pending_present': secondaryPendingPresent,
    'remaining_active_count': activeNotifications.length,
    'remaining_pending_count': pendingRequests.length,
    'remaining_active_ids': activeNotifications.map((n) => n.id).toList(),
    'remaining_pending_ids': pendingRequests.map((p) => p.id).toList(),
  };

  // ignore: avoid_print
  print('[PHASE_2D_NOTIF_CLEANUP_COMPLETED] ${jsonEncode(record)}');

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}
