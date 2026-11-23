import 'package:flutter/services.dart';
import '../../domain/entities/focus_ward_type.dart';
import '../../domain/ports/focus_scheduling_port.dart';

/// Platform implementation of [FocusSchedulingPort] connecting to Android AlarmManager.
class NativeFocusSchedulingPort implements FocusSchedulingPort {
  static const MethodChannel _channel =
      MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');

  final MethodChannel channel;

  NativeFocusSchedulingPort({MethodChannel? customChannel})
      : channel = customChannel ?? _channel;

  @override
  Future<bool> scheduleAlarm({
    required String scheduleId,
    required DateTime triggerAt,
    required String wardTitle,
    required FocusWardType wardType,
  }) async {
    try {
      final result = await channel.invokeMethod<bool>('scheduleAlarm', {
        'scheduleId': scheduleId,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        'wardTitle': wardTitle,
        'wardType': wardType.name,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> cancelAlarm(String scheduleId) async {
    try {
      final result = await channel.invokeMethod<bool>('cancelAlarm', {
        'scheduleId': scheduleId,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    try {
      final permissions =
          await channel.invokeMapMethod<String, dynamic>('checkPermissions');
      return permissions?['canScheduleExactAlarms'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    try {
      await channel.invokeMethod<void>('openExactAlarmSettings');
    } on PlatformException {
      // Ignore or log error
    }
  }
}
