import 'dart:async';
import 'package:flutter/services.dart';

class FocusPoCPermissionStatus {
  final bool hasUsageAccess;
  final bool hasOverlayPermission;
  final bool canScheduleExactAlarms;

  const FocusPoCPermissionStatus({
    required this.hasUsageAccess,
    required this.hasOverlayPermission,
    required this.canScheduleExactAlarms,
  });

  bool get isAllGranted => hasUsageAccess && hasOverlayPermission;

  factory FocusPoCPermissionStatus.fromMap(Map<dynamic, dynamic> map) {
    return FocusPoCPermissionStatus(
      hasUsageAccess: map['hasUsageAccess'] as bool? ?? false,
      hasOverlayPermission: map['hasOverlayPermission'] as bool? ?? false,
      canScheduleExactAlarms: map['canScheduleExactAlarms'] as bool? ?? false,
    );
  }
}

class FocusPoCChannel {
  static const MethodChannel _methodChannel =
      MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');
  static const EventChannel _eventChannel =
      EventChannel('com.shadyatef.hafiz_alahd/focus_poc_events');

  static Stream<Map<String, dynamic>>? _eventStream;

  /// Stream of real-time events emitted by the native FocusPoCService
  static Stream<Map<String, dynamic>> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _eventStream!;
  }

  /// Checks whether required system permissions are currently granted
  static Future<FocusPoCPermissionStatus> checkPermissions() async {
    try {
      final res = await _methodChannel.invokeMethod('checkPermissions');
      if (res is Map) {
        return FocusPoCPermissionStatus.fromMap(res);
      }
    } catch (e) {
      // Fallback
    }
    return const FocusPoCPermissionStatus(
      hasUsageAccess: false,
      hasOverlayPermission: false,
      canScheduleExactAlarms: false,
    );
  }

  /// Launches Android System Settings for Usage Access
  static Future<void> openUsageAccessSettings() async {
    await _methodChannel.invokeMethod('openUsageAccessSettings');
  }

  /// Launches Android System Settings for Draw Over Other Apps
  static Future<void> openOverlaySettings() async {
    await _methodChannel.invokeMethod('openOverlaySettings');
  }

  /// Launches Android System Settings for Exact Alarms (Android 12+)
  static Future<void> openExactAlarmSettings() async {
    await _methodChannel.invokeMethod('openExactAlarmSettings');
  }

  /// Starts the native Focus PoC Foreground Service
  static Future<bool> startMonitoring({
    String wardTitle = 'أذكار الصباح',
    String? sessionId,
  }) async {
    final res = await _methodChannel.invokeMethod<bool>('startMonitoring', {
      'wardTitle': wardTitle,
      'sessionId': sessionId,
    });
    return res ?? false;
  }

  /// Stops the native Focus PoC Foreground Service
  static Future<bool> stopMonitoring() async {
    final res = await _methodChannel.invokeMethod<bool>('stopMonitoring');
    return res ?? false;
  }

  /// Checks if the native service is actively running
  static Future<bool> isServiceRunning() async {
    final res = await _methodChannel.invokeMethod<bool>('isServiceRunning');
    return res ?? false;
  }

  /// Retrieves the comprehensive status of the native enforcement service
  static Future<Map<String, dynamic>> getEnforcementStatus() async {
    try {
      final res = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getEnforcementStatus',
      );
      return res ?? {'isRunning': false, 'state': 'stopped'};
    } catch (_) {
      return {'isRunning': false, 'state': 'stopped'};
    }
  }

  /// Immediately polls current foreground app from native side
  static Future<Map<String, dynamic>> getCurrentForegroundApp() async {
    final res = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getCurrentForegroundApp',
    );
    return res ?? {'packageName': null, 'isExempted': true};
  }

  /// Retrieves pending ward deep link target if app was launched/resumed from shield overlay
  static Future<String?> getPendingWardIntent() async {
    try {
      final res = await _methodChannel.invokeMethod<String>('getPendingWardIntent');
      return res;
    } catch (_) {
      return null;
    }
  }
}
