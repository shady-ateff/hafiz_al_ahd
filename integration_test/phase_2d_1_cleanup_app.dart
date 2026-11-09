import 'dart:convert';
import 'dart:developer';

import 'package:alarm/alarm.dart';
import 'package:flutter/widgets.dart';

/// Phase 2D.1 Physical Delivery Surgical Cleanup App.
///
/// Cancels target alarm #999901 without blanket wipes.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log('🔧 [Cleanup Harness] Initializing Alarm plugin...');
  await Alarm.init();

  const int testAlarmId = 999901;
  final stopped = await Alarm.stop(testAlarmId);
  final remaining = await Alarm.getAlarm(testAlarmId);
  final allAlarms = await Alarm.getAlarms();

  final record = {
    'action': 'SURGICAL_CLEANUP_COMPLETED',
    'target_id': testAlarmId,
    'stop_returned_true': stopped,
    'target_absent': remaining == null,
    'non_target_alarm_count': allAlarms.length,
  };
  // ignore: avoid_print
  print('[PHASE_2D_CLEANUP_COMPLETED] ${jsonEncode(record)}');

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}

