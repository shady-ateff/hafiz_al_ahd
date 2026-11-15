// lib/features/notifications/domain/repositories/base_notification_repository.dart

import '../entities/schedule_operation_result.dart';

abstract class BaseNotificationRepository {
  /// تهيئة الإشعارات (Initialization)
  Future<void> initialize();

  /// طلب صلاحيات الإشعارات من المستخدم
  Future<void> requestPermissions();

  /// جدولة إشعار الصلاة
  Future<void> schedulePrayerNotification({
    required int id, // رقم مميز لكل صلاة
    required String title, // اسم الصلاة (مثال: حان الآن موعد صلاة الظهر)
    required String body, // الدعاء أو التفاصيل
    required DateTime scheduledTime, // وقت الصلاة بالظبط
    String? soundName,
    String? payload,
  });

  Future<void> showStickyNotification({
    required int id,
    required String title,
    required String body,
    required DateTime nextPrayerTime,
  });
  Future<int> getPendingNotificationsCount();

  /// إلغاء كل الإشعارات (مفيدة لو اليوزر غير مكانه فبنمسح القديم ونجدول من جديد)
  Future<void> cancelAllNotifications();
  Future<void> cancelNotification(int id);
  Future<void> cancelActivePrayerNotification();
  
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  });

  /// جدولة منبه أذان باستخدام باكيدج alarm (صوت محمي لا يتوقف)
  Future<void> scheduleAdhanAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String assetAudioPath,
    double? volume, // 👈 إضافة متغير الصوت
    bool enableVibration = true, // 👈 إضافة متغير الاهتزاز
    bool androidFullScreenIntent = true,
    String? stopButton = 'إيقاف الأذان',
  });

  /// إلغاء كل المنبهات (الأذان) اللي اتجدولت عن طريق باكيدج alarm
  Future<void> cancelAllAlarms();

  /// إلغاء منبه محدد بأمان وفق عقد التحقق وسياسة Fail-Closed
  /// يحمي الأذان النشط والمنبهات القريبة من الانطلاق ويتحقق من إزالة السجل
  Future<EventCancellationStatus> cancelAlarmSafely(
    int id, {
    DateTime? expectedScheduledTime,
    String? expectedAssetAudioPath,
  });

  /// إلغاء إشعار محدد بأمان وفق عقد التحقق وسياسة Fail-Closed
  /// يتحقق من إزالة الـ pending request من FLN queue وينظف الـ fingerprint
  Future<EventCancellationStatus> cancelNotificationSafely(int id);

  /// التحقق من مطابقة المنبه المسجل في Level 2 (SQLite registry)
  Future<EventVerificationStatus> verifyAlarm({
    required int id,
    required DateTime expectedScheduledTime,
    String? expectedAssetAudioPath,
    double? expectedVolume,
    bool? expectedEnableVibration,
  });

  /// التحقق من مطابقة الإشعار المسجل في Level 2 (FLN queue + SharedPreferences ledger)
  Future<EventVerificationStatus> verifyNotification({
    required int id,
    required DateTime expectedScheduledTime,
    required String expectedPayload,
    String? expectedTitle,
    String? expectedBody,
    String? expectedChannelId,
    String? expectedSoundSource,
  });
}
