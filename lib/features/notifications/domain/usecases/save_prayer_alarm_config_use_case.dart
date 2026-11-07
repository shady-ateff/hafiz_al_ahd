import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';

class SavePrayerAlarmConfigUseCase {
  final BasePrayerAlarmConfigRepository repository;

  SavePrayerAlarmConfigUseCase(this.repository);

  Future<void> execute(PrayerAlarmConfig config) async {
    return await repository.saveConfig(config);
  }
}

