// lib/features/notifications/domain/repositories/base_notification_repository.dart

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
  // في الملفين (الـ Repo والـ UseCase) ضيف المتغير ده:
  Future<void> execute({
    // أو schedulePrayerNotification في الـ Repo
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName, // 👈 المتغير الجديد (اختياري)
  });
}
