import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/app/view/app.dart';
import 'package:hafiz_al_ahd/core/services/desktop_window_service.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences pref;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // جلب اسم التطبيق الأصلي
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    // التسجيل في كشكول الويندوز (الـ Startup)
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: ['--hidden'], // كلمة السر اللي هتتبعت لما الويندوز يصحى
    );

    await launchAtStartup.enable(); // تفعيل الفتح مع الجهاز

    // تشغيل المايسترو اللي عملناه في الملف التاني
    await DesktopWindowService.initialize(args);
  }

  // Initialize notifications using Clean Architecture Repository
  final notificationRepository = NotificationRepositoryImpl();
  await notificationRepository.initialize();
  await notificationRepository.requestPermissions();

  WakelockPlus.enable(); // Keep the screen awake
  HijriCalendar.setLocal("ar"); // Set Hijri calendar locale to Arabic
  pref = await SharedPreferences.getInstance();
  runApp(App(sharedPreferences: pref));
}
