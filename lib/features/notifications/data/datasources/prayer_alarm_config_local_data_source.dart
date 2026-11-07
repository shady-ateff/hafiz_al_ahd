import 'dart:convert';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

abstract class BasePrayerAlarmConfigLocalDataSource {
  Future<Map<PrayerId, PrayerAlarmConfigModel>> getConfigs();
  Future<PrayerAlarmConfigModel> getConfig(PrayerId prayerId);
  Future<void> saveConfig(PrayerAlarmConfigModel config);
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfigModel> configs);
  Future<bool> migrateLegacyIfNeeded();
  Future<int> getVersion();
}

class PrayerAlarmConfigLocalDataSourceImpl implements BasePrayerAlarmConfigLocalDataSource {
  final SharedPreferences prefs;

  static const String versionKey = 'prayer_alarm_config_version';
  static const int currentVersion = 1;

  static const String legacyAdhanStyleKey = 'adhanStyle';
  static const String configsJsonKey = 'prayer_alarm_configs_json';

  static String alarmTypeKey(String prayerKey) => 'prayer_alarm_type_$prayerKey';
  static String alarmSoundKey(String prayerKey) => 'prayer_alarm_sound_$prayerKey';

  static const String defaultFajrSound = 'assets/sounds/fajr_azan.mp3';
  static const String defaultGeneralSound = 'assets/sounds/adhan.mp3';

  PrayerAlarmConfigLocalDataSourceImpl({required this.prefs});

  @override
  Future<int> getVersion() async {
    return prefs.getInt(versionKey) ?? 0;
  }

  @override
  Future<bool> migrateLegacyIfNeeded() async {
    final int version = prefs.getInt(versionKey) ?? 0;

    // Idempotency check: if version is current, verify all configs exist without overwriting
    if (version >= currentVersion) {
      bool allExist = true;
      for (final id in PrayerId.values) {
        if (!prefs.containsKey(alarmTypeKey(id.key))) {
          allExist = false;
          break;
        }
      }
      if (allExist) {
        return false; // Already migrated, do nothing to preserve user edits
      }
    }

    log("🔄 [PrayerAlarmConfigMigration] Executing versioned migration to v$currentVersion...");

    // 1. Read & validate legacy preference
    final String? legacyStyleRaw = prefs.getString(legacyAdhanStyleKey);
    final PrayerAlarmType resolvedType;

    if (legacyStyleRaw == null) {
      // Legacy default
      resolvedType = PrayerAlarmType.alarm;
    } else {
      switch (legacyStyleRaw.toLowerCase().trim()) {
        case 'alarm':
          resolvedType = PrayerAlarmType.alarm;
          break;
        case 'notification':
          resolvedType = PrayerAlarmType.notification;
          break;
        case 'none':
          resolvedType = PrayerAlarmType.off;
          break;
        default:
          log("⚠️ [PrayerAlarmConfigMigration] Unrecognized legacy adhanStyle '$legacyStyleRaw'. Falling back to alarm.");
          resolvedType = PrayerAlarmType.alarm;
          break;
      }
    }

    // 2. Build in-memory configurations for all five prayers
    final Map<PrayerId, PrayerAlarmConfigModel> configs = {};
    for (final id in PrayerId.values) {
      // If user had already modified an individual key during a partial run, preserve it
      final existingKeyVal = prefs.getString(alarmTypeKey(id.key));
      final PrayerAlarmType type = existingKeyVal != null
          ? PrayerAlarmType.fromKey(existingKeyVal, fallback: resolvedType)
          : resolvedType;

      configs[id] = PrayerAlarmConfigModel(
        prayerId: id,
        alarmType: type,
      );
    }

    // 3. Persist individual keys and sounds
    for (final entry in configs.entries) {
      final id = entry.key;
      final config = entry.value;

      await prefs.setString(alarmTypeKey(id.key), config.alarmType.key);

      // Preserve or set default sound paths
      if (!prefs.containsKey(alarmSoundKey(id.key))) {
        final sound = (id == PrayerId.fajr) ? defaultFajrSound : defaultGeneralSound;
        await prefs.setString(alarmSoundKey(id.key), sound);
      }
    }

    // 4. Persist atomic JSON payload
    final jsonMap = configs.map(
      (key, value) => MapEntry(key.key, value.toJson()),
    );
    await prefs.setString(configsJsonKey, json.encode(jsonMap));

    // 5. Read-back verification
    for (final id in PrayerId.values) {
      final verified = prefs.getString(alarmTypeKey(id.key));
      if (verified == null) {
        throw StateError("Migration verification failed: missing key for ${id.key}");
      }
    }

    // 6. Write version marker only after complete verification
    await prefs.setInt(versionKey, currentVersion);
    log("✅ [PrayerAlarmConfigMigration] Migration to v$currentVersion completed successfully!");

    return true;
  }

  @override
  Future<Map<PrayerId, PrayerAlarmConfigModel>> getConfigs() async {
    // Ensure migrated if needed
    final version = prefs.getInt(versionKey) ?? 0;
    if (version < currentVersion) {
      await migrateLegacyIfNeeded();
    }

    // Try reading from atomic JSON payload first
    final String? jsonStr = prefs.getString(configsJsonKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(jsonStr) as Map<String, dynamic>;
        final Map<PrayerId, PrayerAlarmConfigModel> result = {};
        for (final id in PrayerId.values) {
          if (decoded.containsKey(id.key)) {
            result[id] = PrayerAlarmConfigModel.fromJson(
              decoded[id.key] as Map<String, dynamic>,
            );
          }
        }
        if (result.length == PrayerId.values.length) {
          return result;
        }
      } catch (e) {
        log("⚠️ Error parsing atomic configs JSON: $e. Falling back to multi-key reading.");
      }
    }

    // Fallback: Read individual keys
    final Map<PrayerId, PrayerAlarmConfigModel> result = {};
    for (final id in PrayerId.values) {
      final rawType = prefs.getString(alarmTypeKey(id.key));
      final alarmType = PrayerAlarmType.fromKey(rawType, fallback: PrayerAlarmType.alarm);
      result[id] = PrayerAlarmConfigModel(prayerId: id, alarmType: alarmType);
    }
    return result;
  }

  @override
  Future<PrayerAlarmConfigModel> getConfig(PrayerId prayerId) async {
    final all = await getConfigs();
    return all[prayerId] ??
        PrayerAlarmConfigModel(prayerId: prayerId, alarmType: PrayerAlarmType.alarm);
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfigModel config) async {
    await prefs.setString(alarmTypeKey(config.prayerId.key), config.alarmType.key);

    // Update atomic JSON payload as well
    final current = await getConfigs();
    current[config.prayerId] = config;
    final jsonMap = current.map(
      (key, value) => MapEntry(key.key, value.toJson()),
    );
    await prefs.setString(configsJsonKey, json.encode(jsonMap));
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfigModel> configs) async {
    for (final entry in configs.entries) {
      await prefs.setString(alarmTypeKey(entry.key.key), entry.value.alarmType.key);
    }
    final jsonMap = configs.map(
      (key, value) => MapEntry(key.key, value.toJson()),
    );
    await prefs.setString(configsJsonKey, json.encode(jsonMap));
  }
}

