import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';

class SchedulePrayerUseCase {
  final BaseNotificationRepository repository;

  SchedulePrayerUseCase(this.repository);

  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  }) async {
    // هنا ممكن نضيف أي Logic مستقبلاً (مثلاً: لو وقت الصلاة في الماضي متعملش جدولة)
    if (scheduledTime.isBefore(DateTime.now())) return;

    return await repository.execute(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
      payload: payload,
    );
  }
}
