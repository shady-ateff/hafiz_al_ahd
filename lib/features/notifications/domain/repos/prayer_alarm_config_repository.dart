import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

/// Repository interface for managing per-prayer alarm configurations.
abstract class BasePrayerAlarmConfigRepository {
  /// Retrieves configurations for all five prayers.
  /// If not yet migrated or initialized, performs migration or provides safe defaults.
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs();

  /// Retrieves the configuration for a specific prayer.
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId);

  /// Persists the configuration for a single prayer.
  Future<void> saveConfig(PrayerAlarmConfig config);

  /// Persists configurations for all five prayers in a single payload.
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> configs);

  /// Runs the versioned migration if `prayer_alarm_config_version` is missing or outdated.
  /// Returns `true` if migration was executed, or `false` if already migrated (idempotent).
  Future<bool> migrateLegacyConfigsIfNeeded();

  /// Gets the current migration version (0 if not migrated).
  Future<int> getMigrationVersion();
}

