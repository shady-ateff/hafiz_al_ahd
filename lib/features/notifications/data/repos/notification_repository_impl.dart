import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationRepositoryImpl implements BaseNotificationRepository {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
          windows: initializationSettingsWindows,
        );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  @override
  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

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
  Future<void> schedulePrayerNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
  }) async {
    // 👈 1. غيرنا الـ ID لـ v3 عشان أندرويد يعمل قناة جديدة إجبارياً
    // غير السطر ده:
    // غيرنا v4 لـ v5 عشان نكريت قناة زيرو بصوت جديد
    String channelId = soundName != null
        ? 'prayer_channel_v5_$soundName'
        : 'prayer_channel_v5_default';
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      'مواقيت الصلاة',
      channelDescription: 'إشعارات التنبيه بأوقات الصلاة والأذان',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      // 👈 2. تمرير الصوت من غير .mp3
      sound: soundName != null
          ? RawResourceAndroidNotificationSound(soundName)
          : null,
      // 👈 3. السطر السحري اللي كان ناقص عندك:
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    // 👈 4. ضفنا إعدادات iOS بالمرة عشان لما تيجي ترفع على أبل ميعملش مشكلة
    DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true,
      sound: soundName != null ? '$soundName.mp3' : null,
    );

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    NotificationDetails platformSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails, // 👈 بصيناها هنا
      windows: windowsDetails,
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final delay = scheduledTime.difference(DateTime.now());
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
      return;
    }

    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      tz.local,
    );

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

  @override
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) return;

    return await schedulePrayerNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
    );
  }
}
