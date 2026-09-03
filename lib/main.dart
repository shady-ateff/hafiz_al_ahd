import 'dart:developer';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/app/view/app.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart' as di;
import 'package:hafiz_al_ahd/core/services/background_service_manager.dart'; // 👈 استيراد خدمة الخلفية
import 'package:hafiz_al_ahd/core/services/desktop_window_service.dart';
import 'package:hafiz_al_ahd/features/main/presentation/screens/main_screen.dart';
// 👈 استدعي الـ Base بدلاً من الـ Impl
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/screens/adhan_screen.dart';
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
bool _isAdhanScreenActive = false; // 👈 علم لمنع فتح الشاشة مرتين

void _openAdhanScreen({required String payload, int? notificationId, String? prayerName}) {
  if (_isAdhanScreenActive) return;
  _isAdhanScreenActive = true;
  
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => AdhanScreen(
        payload: payload,
        notificationId: notificationId,
        prayerName: prayerName,
      ),
    ),
  ).then((_) {
    // لما الشاشة تقفل، نرجع العلم لـ false
    _isAdhanScreenActive = false;
  });
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  await Alarm.init(); // 👈 تهيئة باكيدج المنبه (للأذان)

  // 👈 منطق تهجير (Migration) للمستخدمين القدامى: مسح الإشعار الثابت القديم (الوهمي) اللي كان رقمه 999
  FlutterLocalNotificationsPlugin().cancel(id: 999);

  await BackgroundServiceManager.initializeService(); // 👈 تهيئة خدمة الخلفية الحقيقية (للإشعار الثابت)
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
  // الصلاحيات الآن بتتطلب من شاشة الـ Onboarding خطوة بخطوة

  HijriCalendar.setLocal("ar"); // Set Hijri calendar locale to Arabic

  // ---------------------------------------------------------
  // 5. الاستماع لـ Stream الإشعارات العادية (flutter_local_notifications)
  //    بس بنفلتر: الـ sticky والـ iqama مبيفتحوش شاشة الأذان
  // ---------------------------------------------------------
  selectNotificationStream.stream.listen((String? payload) {
    if (payload == null || payload == 'sticky') {
      // Stay on the main screen, do not open AdhanScreen.
      return;
    }

    if (payload.startsWith('adhan_')) {
      _openAdhanScreen(payload: payload);
    } else if (payload.startsWith('azkar_')) {
      String? category;
      if (payload == 'azkar_morning') category = 'أذكار الصباح';
      else if (payload == 'azkar_evening') category = 'أذكار المساء';
      else if (payload == 'azkar_after_prayer') category = 'أذكار بعد الصلاة';

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainScreen(initialTab: 2, initialAzkarCategory: category),
        ),
        (route) => false,
      );
    }
    // أي payload تاني (iqama_, test, إلخ) مبيفتحش شاشة الأذان
  });

  // ---------------------------------------------------------
  // 6. تشغيل التطبيق
  // ---------------------------------------------------------
  runApp(const App()); // خليها const لو الـ App ويدجت تدعم ده

  // ---------------------------------------------------------
  // 7. بعد ما الـ Navigator يبقى جاهز، نعمل كل حاجة تانية
  // ---------------------------------------------------------
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // 7a. الاستماع لباكيدج المنبه (alarm) — لما الأذان يرن
    Alarm.ringing.listen((AlarmSet alarmSet) async {
      // إذا كان هناك منبهات متعددة رنت في نفس اللحظة (مثلاً الجهاز كان مغلقاً)، نحتفظ بالأحدث فقط
      AlarmSettings? latestAlarm;
      for (final alarm in alarmSet.alarms) {
        if (latestAlarm != null) {
          // أوقف المنبه القديم بصمت
          await Alarm.stop(latestAlarm.id);
          log("[alarm ringing] Stopped older alarm: ${latestAlarm.id} due to stacking");
        }
        latestAlarm = alarm;
      }
      
      if (latestAlarm != null) {
        // إذا كان الأذان الأحدث قد مر على وقته أكثر من 5 دقائق (بسبب إغلاق الهاتف)، نتجاهله
        if (DateTime.now().difference(latestAlarm.dateTime).inMinutes > 5) {
           await Alarm.stop(latestAlarm.id);
           log("[alarm ringing] Stopped expired alarm: ${latestAlarm.id}");
           return;
        }

        log(
          "[alarm ringing] Alarm ringing: ${latestAlarm.id} - ${latestAlarm.notificationSettings.title}",
        );
        _openAdhanScreen(
          payload: 'adhan_${latestAlarm.id}_${latestAlarm.notificationSettings.title}',
          notificationId: latestAlarm.id,
          prayerName: latestAlarm.notificationSettings.title,
        );
      }
    });

    // 7b. التحقق من إشعارات flutter_local_notifications (عشان نعرف لو اليوزر داس على حاجة)
    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await FlutterLocalNotificationsPlugin()
            .getNotificationAppLaunchDetails();

    bool launchedFromSticky = false;

    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      final payload =
          notificationAppLaunchDetails?.notificationResponse?.payload;
          
      if (payload == 'sticky') {
        launchedFromSticky = true;
      }

      // نستخدم نفس اللوجيك اللي فوق لتوحيد التوجيه (الأذان أو الأذكار)
      if (payload != null) {
        if (payload.startsWith('adhan_')) {
          _openAdhanScreen(payload: payload);
        } else if (payload.startsWith('azkar_')) {
          String? category;
          if (payload == 'azkar_morning') category = 'أذكار الصباح';
          else if (payload == 'azkar_evening') category = 'أذكار المساء';
          else if (payload == 'azkar_after_prayer') category = 'أذكار بعد الصلاة';

          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => MainScreen(initialTab: 2, initialAzkarCategory: category),
            ),
            (route) => false,
          );
        }
      }
    }

    // 7c. لو التطبيق اتفتح وفيه منبه بيرن دلوقتي (app was terminated)
    final alarms = await Alarm.getAlarms();
    AlarmSettings? latestRingingAlarm;
    
    for (final alarm in alarms) {
      if (await Alarm.isRinging(alarm.id)) {
        if (latestRingingAlarm != null) {
           await Alarm.stop(latestRingingAlarm.id);
           log("[cold start] Stopped older ringing alarm: ${latestRingingAlarm.id}");
        }
        latestRingingAlarm = alarm;
      }
    }
    
    if (latestRingingAlarm != null) {
        if (launchedFromSticky) {
           // لو اليوزر داس على الـ sticky notification، نوقف المنبه بصمت ومبنفتحش شاشة الأذان
           await Alarm.stop(latestRingingAlarm.id);
           log("[cold start] Stopped ringing alarm silently because launched from sticky: ${latestRingingAlarm.id}");
        } else if (DateTime.now().difference(latestRingingAlarm.dateTime).inMinutes > 5) {
           await Alarm.stop(latestRingingAlarm.id);
           log("[cold start] Stopped expired ringing alarm: ${latestRingingAlarm.id}");
        } else {
          _openAdhanScreen(
            payload: 'adhan_${latestRingingAlarm.id}_${latestRingingAlarm.notificationSettings.title}',
            notificationId: latestRingingAlarm.id,
            prayerName: latestRingingAlarm.notificationSettings.title,
          );
        }
    }
  });
}
