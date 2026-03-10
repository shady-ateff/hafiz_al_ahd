// lib/features/notifications/data/repositories/notification_repository_impl.dart

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

    // تجميع الإعدادات
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
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
  Future<void> schedulePrayerNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
  }) async {
    // تحويل الوقت العادي لـ توقيت محلي دقيق (Timezone)
    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      tz.local,
    );

    // إعدادات الإشعار نفسه (القناة، الأهمية، الصوت)
    final AndroidNotificationDetails
    androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'prayer_times_channel', // ID القناة (مهم جداً ويفضل يكون ثابت)
      'مواقيت الصلاة', // اسم القناة اللي بيظهر لليوزر في الإعدادات
      channelDescription: 'إشعارات التنبيه بأوقات الصلاة والأذان',
      importance: Importance.max, // عشان يظهر Pop-up من فوق
      priority: Priority.high,
      playSound: true,
      sound: soundName != null ?  RawResourceAndroidNotificationSound(soundName) : const RawResourceAndroidNotificationSound('adhan'), // 👈 هنفعل السطر ده لما نحط ملف الأذان الـ mp3
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    // أمر الجدولة الفعلي
    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduledTime,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode
          .exactAllowWhileIdle, // عشان يضرب في وقته حتى لو الجهاز في وضع توفير طاقة
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
