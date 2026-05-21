import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';

enum PermissionResult {
  granted,
  denied,
  permanentlyDenied
}

enum PermissionType {
  location,
  notification,
  exactAlarm,
  batteryOptimization,
  autoStart,
  xiaomiCustom,
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

  /// طلب صلاحية التشغيل التلقائي (Auto Start) للأجهزة اللي بتدعمها (شاومي، أوبو، الخ)
  static Future<PermissionResult> requestAutoStart() async {
    try {
      final available = await isAutoStartAvailable;
      if (available == true) {
        await getAutoStartPermission();
      }
    } catch (e) {
      // Ignore if not available
    }
    return PermissionResult.granted;
  }

  /// توجيه مستخدمي شاومي لصفحة الصلاحيات الخاصة
  static Future<PermissionResult> requestXiaomiPermissions() async {
    try {
      // 👈 استخدام android_intent_plus للوصول المباشر لصفحة الصلاحيات الخفية في MIUI
      const intent = AndroidIntent(
        action: 'miui.intent.action.APP_PERM_EDITOR',
        arguments: <String, dynamic>{'extra_pkgname': 'com.shadyatef.hafiz_alahd'},
      );
      await intent.launch();
    } catch (e) {
      // لو فشل (مثلاً الروم متعدلة بزيادة)، افتح الإعدادات العادية
      await openAppSettings();
    }
    
    // منقدرش نتحقق برمجياً اليوزر وافق ولا لأ، فبنعتبرها تمت عشان يكمل الـ Onboarding
    return PermissionResult.granted;
  }

  static PermissionResult _mapStatus(PermissionStatus status) {
    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }
}