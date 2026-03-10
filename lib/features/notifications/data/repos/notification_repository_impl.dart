// lib/features/notifications/data/repositories/notification_repository_impl.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationRepositoryImpl implements BaseNotificationRepository {
  // إنشاء الـ Instance الخاص بالمكتبة
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    // 1. تهيئة الـ Timezones (خطوة إجبارية عشان الإشعار يضرب في وقته بالظبط)
    tz.initializeTimeZones();

    // 2. إعدادات الأندرويد
    // '@mipmap/ic_launcher' بتسحب أيقونة التطبيق الحالية اللي عملناها بـ launcher_icons
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. إعدادات الـ iOS (استعداداً للـ App Store)
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'Hafiz Al Ahd',
          appUserModelId: '234567890',
          guid: '12345678-1234-5678-1234-567812345678',
        );
    // تجميع الإعدادات
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
          windows: initializationSettingsWindows,
        );

    // تهيئة المكتبة
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  @override
  Future<void> requestPermissions() async {
    // Android permissions
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    // iOS permissions
    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  @override
  @override
  Future<void> schedulePrayerNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
  }) async {
    
    // إعدادات الأندرويد
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'prayer_times_channel',
      'مواقيت الصلاة',
      channelDescription: 'إشعارات التنبيه بأوقات الصلاة والأذان',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: soundName != null ? RawResourceAndroidNotificationSound(soundName) : null,
    );

    // إعدادات الويندوز
    const WindowsNotificationDetails windowsDetails = WindowsNotificationDetails(); 

    NotificationDetails platformSpecifics = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    // ==========================================
    // 👈 السحر هنا: لو إحنا على ويندوز، هنستخدم Timer
    // ==========================================
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // نحسب الفرق بين دلوقتي وموعد الإشعار
      final delay = scheduledTime.difference(DateTime.now());
      
      // لو الوقت لسة مجاش، نعمل Timer
      if (!delay.isNegative) {
        Timer(delay, () async {
          await _flutterLocalNotificationsPlugin.show(
            id: id,
            title: title,
            body: body,
            notificationDetails: platformSpecifics,
          );
        });
      }
      return; // اخرج من الدالة عشان ميكملش لكود الأندرويد
    }

    // ==========================================
    // 👈 لو إحنا على أندرويد/iOS، نستخدم الجدولة العادية
    // ==========================================
    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduledTime,
      notificationDetails: platformSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
  @override
  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  // في الملفين (الـ Repo والـ UseCase) ضيف المتغير ده:
  @override
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
  }) async {
    // هنا ممكن نضيف أي Logic مستقبلاً (مثلاً: لو وقت الصلاة في الماضي متعملش جدولة)
    if (scheduledTime.isBefore(DateTime.now())) return;

    return await schedulePrayerNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
    );
  }
}
