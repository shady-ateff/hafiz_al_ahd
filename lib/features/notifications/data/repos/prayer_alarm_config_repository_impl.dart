import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';

class PrayerAlarmConfigRepositoryImpl implements BasePrayerAlarmConfigRepository {
  final BasePrayerAlarmConfigLocalDataSource localDataSource;

  PrayerAlarmConfigRepositoryImpl({required this.localDataSource});

  @override
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs() async {
    final models = await localDataSource.getConfigs();
    return models.map((key, value) => MapEntry(key, value));
  }

  @override
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId) async {
    return await localDataSource.getConfig(prayerId);
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfig config) async {
    final model = PrayerAlarmConfigModel.fromEntity(config);
    await localDataSource.saveConfig(model);
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> configs) async {
    final models = configs.map(
      (key, value) => MapEntry(key, PrayerAlarmConfigModel.fromEntity(value)),
    );
    await localDataSource.saveAllConfigs(models);
  }

  @override
  Future<bool> migrateLegacyConfigsIfNeeded() async {
    return await localDataSource.migrateLegacyIfNeeded();
  }

  @override
  Future<int> getMigrationVersion() async {
    return await localDataSource.getVersion();
  }
}

