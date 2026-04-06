import 'dart:developer';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/app/view/app.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart' as di;
import 'package:hafiz_al_ahd/core/services/desktop_window_service.dart';
import 'package:hafiz_al_ahd/core/utils/app_permission.dart';
import 'package:hafiz_al_ahd/core/utils/home_widget_helper.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
// 👈 استدعي الـ Base بدلاً من الـ Impl
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/screens/adhan_screen.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
// استدعاء ملف الـ Data اللي فيه الـ Stream (أو نقله لملف منفصل أفضل مستقبلاً)
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';

// 👈 الدالة دي بتتحط بره أي كلاس، مثلاً في ملف منفصل أو فوق في main.dart


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  // ---------------------------------------------------------
  // 1. تهيئة المنطقة الزمنية (عشان نمنع ضرب الإشعارات كلها مع بعض)
  // ---------------------------------------------------------
  tz.initializeTimeZones();
  try {
    final TimezoneInfo timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(
      tz.getLocation(timeZoneName.localizedName?.name ?? 'Africa/Cairo'),
    ); // حاول تجيب المنطقة الزمنية الحقيقية، ولو فشل استخدم القاهرة كاحتياطي
  } catch (e) {
    tz.setLocalLocation(tz.getLocation('Africa/Cairo')); // احتياطي
  }

  // ---------------------------------------------------------
  // 2. تشغيل الـ Service Locator أول حاجة (تجهيز المخزن)
  // ---------------------------------------------------------
  await di.init();

  // ---------------------------------------------------------
  // 3. إعدادات الويندوز والديسكتوب
  // ---------------------------------------------------------
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: ['--hidden'],
    );
    await launchAtStartup.enable();
    await DesktopWindowService.initialize(args);
  }

  // ---------------------------------------------------------
  // 4. تهيئة الإشعارات (بنطلبها من الـ DI مش بنعملها بإيدنا)
  // ---------------------------------------------------------
  final notificationRepository = di.sl<BaseNotificationRepository>();
  await notificationRepository.initialize();
  await AppPermissions.requestProductionPermissions(); // نقلتها هنا عشان تكون قبل طلب صلاحيات الإشعارات المخصصة
  await notificationRepository.requestPermissions();

  HijriCalendar.setLocal("ar"); // Set Hijri calendar locale to Arabic

  // ---------------------------------------------------------
  // 5. الاستماع لـ Stream الإشعارات (التصنت على الدوسات)
  // ---------------------------------------------------------
  selectNotificationStream.stream.listen((String? payload) {
    if (payload != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => AdhanScreen(payload: payload)),
      );
    } else {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const AdhanScreen()),
      );
    }
  });

  // ---------------------------------------------------------
  // 6. تشغيل التطبيق والتعامل مع فتح التطبيق من إشعار (Terminated)
  // ---------------------------------------------------------
  runApp(const App()); // خليها const لو الـ App ويدجت تدعم ده

  // بنجيب التفاصيل بعد الـ DI
  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
      await FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails();

  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const AdhanScreen()),
      );
    });
  }
}
