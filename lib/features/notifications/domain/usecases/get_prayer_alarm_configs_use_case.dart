import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';

class GetPrayerAlarmConfigsUseCase {
  final BasePrayerAlarmConfigRepository repository;

  GetPrayerAlarmConfigsUseCase(this.repository);

  Future<Map<PrayerId, PrayerAlarmConfig>> execute() async {
    return await repository.getConfigs();
  }
}

