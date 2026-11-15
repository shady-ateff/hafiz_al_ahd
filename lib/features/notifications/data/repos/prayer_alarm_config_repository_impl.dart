import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';

class PrayerAlarmConfigRepositoryImpl implements BasePrayerAlarmConfigRepository {
  final BasePrayerAlarmConfigLocalDataSource localDataSource;
  final BaseAudioStorageLock audioStorageLock;
  final CustomAudioStorageService storageService;

  PrayerAlarmConfigRepositoryImpl({
    required this.localDataSource,
    required this.audioStorageLock,
    required this.storageService,
  });

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
    Future<void> action() async {
      // Physical existence and strict containment verification guard under lock
      if (config.audioSource is CustomAudioSource) {
        final custom = config.audioSource as CustomAudioSource;
        await storageService.validatePathContainment(custom.localRelativePath);
      }

      final model = PrayerAlarmConfigModel.fromEntity(config);
      await localDataSource.saveConfig(model);
    }

    await audioStorageLock.synchronized(action);
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> configs) async {
    Future<void> action() async {
      // Physical existence and strict containment verification guard under lock
      for (final cfg in configs.values) {
        if (cfg.audioSource is CustomAudioSource) {
          final custom = cfg.audioSource as CustomAudioSource;
          await storageService.validatePathContainment(custom.localRelativePath);
        }
      }

      final models = configs.map(
        (key, value) => MapEntry(key, PrayerAlarmConfigModel.fromEntity(value)),
      );
      await localDataSource.saveAllConfigs(models);
    }

    await audioStorageLock.synchronized(action);
  }

  @override
  Future<bool> migrateLegacyConfigsIfNeeded() async {
    return await audioStorageLock.synchronized(() async {
      return await localDataSource.migrateLegacyIfNeeded();
    });
  }

  @override
  Future<int> getMigrationVersion() async {
    return await localDataSource.getVersion();
  }
}

