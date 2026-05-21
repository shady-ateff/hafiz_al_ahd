import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundServiceManager {
  static const String notificationChannelId = 'sticky_countdown_channel_v1';
  static const int notificationId = 8888;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // إعداد قناة الإشعارات الخاصة بالخدمة عشان تشتغل Foreground
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'العد التنازلي للصلاة',
      description: 'يعرض الوقت المتبقي للصلاة القادمة',
      importance: Importance.low, // لا يصدر صوت
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'يتم حساب وقت الصلاة...',
        initialNotificationContent: 'جاري التهيئة',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    // تأكد من أن الخدمة تعمل
    if (!await service.isRunning()) {
      await service.startService();
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // الاستماع للأوامر من الـ UI لتحديث الإشعار
  service.on('updatePrayerNotification').listen((event) {
    if (event != null) {
      final title = event['title'] as String?;
      final body = event['body'] as String?;
      final nextPrayerTimeMs = event['nextPrayerTimeMs'] as int?;

      if (title != null && body != null && nextPrayerTimeMs != null) {
        flutterLocalNotificationsPlugin.show(
          id: BackgroundServiceManager.notificationId,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              BackgroundServiceManager.notificationChannelId,
              'العد التنازلي للصلاة',
              channelDescription: 'يعرض الوقت المتبقي للصلاة القادمة',
              importance: Importance.low,
              priority: Priority.low,
              ongoing: true, // يمنع المسح
              autoCancel: false,
              showWhen: true,
              when: nextPrayerTimeMs, // التايمر المستقبلي
              usesChronometer: true,
              chronometerCountDown: true,
              visibility: NotificationVisibility.public,
            ),
          ),
        );
      }
    }
  });

  // الاستماع لطلب إيقاف الخدمة
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}
