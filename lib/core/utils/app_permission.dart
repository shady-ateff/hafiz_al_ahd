import 'package:permission_handler/permission_handler.dart';

/// نتيجة طلب الصلاحية - الـ UI بيقرر إيه يعمل بناءً عليها
enum PermissionResult {
  granted,         // اتوافق عليها
  denied,          // اترفضت (ممكن يتطلب تاني)
  permanentlyDenied // اترفضت نهائياً (لازم يروح الإعدادات)
}

class PermissionManager {
  /// فتح إعدادات التطبيق - الـ UI بس هو اللي ينادي عليها بعد ما يظهر Dialog
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// طلب صلاحية الموقع الجغرافي
  static Future<PermissionResult> requestLocation() async {
    if (await Permission.locationWhenInUse.isGranted) {
      return PermissionResult.granted;
    }
    final status = await Permission.locationWhenInUse.request();
    return _mapStatus(status);
  }

  /// طلب صلاحية الإشعارات (إلزامي في أندرويد 13+)
  static Future<PermissionResult> requestNotification() async {
    if (await Permission.notification.isGranted) {
      return PermissionResult.granted;
    }
    final status = await Permission.notification.request();
    return _mapStatus(status);
  }

  /// طلب صلاحية المنبه الدقيق (إلزامي في أندرويد 12+)
  static Future<PermissionResult> requestExactAlarm() async {
    // في أندرويد 11 وما قبله الصلاحية دي مسموحة افتراضياً
    if (await Permission.scheduleExactAlarm.isGranted) {
      return PermissionResult.granted;
    }
    final status = await Permission.scheduleExactAlarm.request();
    return _mapStatus(status);
  }

  /// استثناء التطبيق من قيود توفير البطارية (Doze Mode)
  static Future<PermissionResult> requestBatteryOptimization() async {
    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      return PermissionResult.granted;
    }
    final status = await Permission.ignoreBatteryOptimizations.request();
    return _mapStatus(status);
  }

  static PermissionResult _mapStatus(PermissionStatus status) {
    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }
}