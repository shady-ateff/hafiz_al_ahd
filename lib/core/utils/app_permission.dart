import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static Future<void> requestProductionPermissions() async {
    // 1. طلب صلاحية الإشعارات (إجباري في أندرويد 13+)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // 2. طلب صلاحية المنبه الدقيق (إجباري في أندرويد 12+)
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }

    // 3. 👈 الضربة القاضية: استثناء التطبيق من قيود البطارية (Doze Mode)
    // ده اللي هيمنع الموبايل إنه يجمع الإشعارات ويضربها مرة واحدة لما تفتح التطبيق
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }
}