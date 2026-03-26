import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';

class ShowStickyNotificationUseCase {
  final BaseNotificationRepository repository;

  ShowStickyNotificationUseCase(this.repository);

  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime nextPrayerTime,
  }) async {
    return await repository.showStickyNotification(
      id: id,
      title: title,
      body: body,
      nextPrayerTime: nextPrayerTime,
    );
  }
}
