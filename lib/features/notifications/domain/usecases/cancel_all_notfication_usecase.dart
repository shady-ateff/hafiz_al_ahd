
import 'package:alarm/alarm.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';

class CancelAllNotificationsUseCase {
  final BaseNotificationRepository repository;

  CancelAllNotificationsUseCase(this.repository);

  Future<void> execute() async {
    // 👈 مسح كل المنبهات (الأذان) اللي اتجدولت عن طريق باكيدج alarm
    await Alarm.stopAll();
    // 👈 مسح كل الإشعارات العادية (الإقامة + الـ sticky)
    return await repository.cancelAllNotifications();
  }
}