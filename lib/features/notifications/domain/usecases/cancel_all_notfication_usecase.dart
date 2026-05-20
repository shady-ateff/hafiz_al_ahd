
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';

class CancelAllNotificationsUseCase {
  final BaseNotificationRepository repository;

  CancelAllNotificationsUseCase(this.repository);

  Future<void> execute() async {
    return await repository.cancelAllNotifications();
  }
}