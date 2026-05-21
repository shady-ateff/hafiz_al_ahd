import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  static Future<bool> requestLocation() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted || status.isLimited;
  }

  static Future<bool> requestNotification() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> requestExactAlarm() async {
    final status = await Permission.scheduleExactAlarm.request();
    // Android automatically grants Exact Alarms to clock/alarm apps, 
    // but on Android 12+ it prompts. isGranted handles the lifecycle properly.
    return status.isGranted;
  }

  static Future<bool> requestBatteryOptimization() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
