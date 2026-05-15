import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hafiz_al_ahd/main.dart';
import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/screens/adhan_screen.dart';

StreamController<String> selectNotificationStream =
    StreamController<String>.broadcast();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // يشتغل والتطبيق مقفول تماماً
  print('🔔 Background Notification Tapped: \${notificationResponse.payload}');
}

void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) {
  print('🔔 Notification Tapped: \${notificationResponse.payload}');

  if (notificationResponse.id != null && notificationResponse.payload != null) {
    selectNotificationStream.add(notificationResponse.payload!);
  }
}

class NotificationRepositoryImpl implements BaseNotificationRepository {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_stat_icon');

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

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  @override
  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        flutterLocalNotificationsPlugin
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
    bool isAdhan = (soundName == 'adhan' || soundName == 'fajr_azan');
    List<AndroidNotificationAction>? actions;
    if (isAdhan) {
      actions = [
        const AndroidNotificationAction(
          'stop_adhan_action', // ID الخاص بالأكشن
          'إيقاف الأذان',
          showsUserInterface:
              false, // لا يفتح التطبيق، فقط ينفذ الكود في الخلفية
          cancelNotification: true,
        ),
      ];
    }
    String channelId = soundName != null
        ? 'prayer_channel_v8_$soundName'
        : 'prayer_channel_v8_default';
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      'مواقيت الصلاة',
      channelDescription: 'إشعارات التنبيه بأوقات الصلاة والأذان',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: soundName != null
          ? RawResourceAndroidNotificationSound(soundName)
          : null,
      actions: actions, // 👈 أزرار الأكشن (إيقاف الأذان)
      audioAttributesUsage: isAdhan
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      category: isAdhan
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent:
          isAdhan, // لو الأذان، نخليها fullScreen عشان تفتح الشاشة حتى لو التليفون مقفول
      ticker: 'مواقيت الصلاة',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      timeoutAfter: 30 * 60 * 1000, // 30 دقيقة عشان لو ما انضغطش يختفي
      visibility: NotificationVisibility.public,
      enableVibration: true,
      enableLights: true,
      groupKey: 'adhan_group',
      ongoing: isAdhan, // 👈 بتخليه زي إشعار المكالمة مبيتمسحش بالسحب
      autoCancel: !isAdhan, // 👈 تمنع مسحه بمجرد اللمس
    );

    DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true,
      sound: soundName != null ? '$soundName.mp3' : null,
    );

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    NotificationDetails platformSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      windows: windowsDetails,
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final delay = scheduledTime.difference(DateTime.now());
      if (!delay.isNegative) {
        Timer(delay, () async {
          await flutterLocalNotificationsPlugin.show(
            id: id,
            title: title,
            body: body,
            notificationDetails: platformSpecifics,
            payload: 'adhan_screen',
          );
        });
      }
      return;
    }

    String payloadData = isAdhan ? 'adhan_${id}_$title' : 'iqama_${id}_$title';
    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      tz.local,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduledTime,
      notificationDetails: platformSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payloadData, // 👈 بنبعته هنا
    );
  }

  @override
  Future<int> getPendingNotificationsCount() async {
    final pendingRequests = await flutterLocalNotificationsPlugin
        .pendingNotificationRequests();
    return pendingRequests.length;
  }

  @override
  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  @override
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    // 1. نجيب كل الإشعارات اللي ظاهرة في الشاشة دلوقتي
    final List<ActiveNotification> activeNotifications =
        await flutterLocalNotificationsPlugin.getActiveNotifications();

    for (var active in activeNotifications) {
      // 2. نمسح الإشعار لو هو تبع قناة الأذان (ونسيب العداد الثابت لأنه في قناة تانية)
      if (active.channelId != null &&
          active.channelId!.contains('prayer_channel_v8')) {
        await flutterLocalNotificationsPlugin.cancel(id: active.id ?? -1);
      }
    }
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

  @override
  Future<void> showStickyNotification({
    required int id,
    required String title,
    required String body,
    required DateTime nextPrayerTime,
  }) async {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sticky_countdown_channel_v1',
      'العد التنازلي للصلاة',
      channelDescription: 'يعرض الوقت المتبقي للصلاة القادمة',
      importance: Importance.low, // واطي عشان ميعملش صوت كل شوية
      priority: Priority.low,
      ongoing: true, // يمنع اليوزر إنه يمسحه
      autoCancel: false,
      showWhen: true,
      when: nextPrayerTime
          .millisecondsSinceEpoch, // بنديله وقت الصلاة الجاية بالملي ثانية
      usesChronometer: true, // بيشغل العداد
      chronometerCountDown: true, // بيخلي العداد ينزل لتحت
      visibility: NotificationVisibility.public,
      groupKey: 'countdown_group',
    );

    NotificationDetails platformSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(), // الـ iOS ليه حسبة تانية للويدجت
    );

    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformSpecifics,
      payload: 'sticky',
    );
  }
}
