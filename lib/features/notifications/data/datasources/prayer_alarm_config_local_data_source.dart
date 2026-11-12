import 'dart:convert';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
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
  static const int currentVersion = 2;

  static const String legacyAdhanStyleKey = 'adhanStyle';
  static const String configsJsonKey = 'prayer_alarm_configs_json';

  static String alarmTypeKey(String prayerKey) => 'prayer_alarm_type_$prayerKey';
  static String alarmSoundKey(String prayerKey) => 'prayer_alarm_sound_$prayerKey';
  static String alarmVolumeKey(String prayerKey) => 'prayer_alarm_volume_$prayerKey';
  static String alarmVibrationKey(String prayerKey) => 'prayer_alarm_vibration_$prayerKey';

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

    // M2: Future Schema (version > currentVersion) — preserve without downgrade or overwrite
    if (version > currentVersion) {
      log("⚠️ [PrayerAlarmConfigMigration] Future schema version $version detected (current is $currentVersion). Preserving data without downgrade.");
      return false;
    }

    // M1 & M3: Already marked currentVersion (2)
    if (version == currentVersion) {
      final String? jsonStr = prefs.getString(configsJsonKey);
      if (jsonStr != null) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          final hasAllPrayers = PrayerId.values.every((id) => decoded.containsKey(id.key));
          if (hasAllPrayers) {
            return false; // M1: Fully valid v2, no-op. Preserves user edits.
          }
          log("⚠️ [PrayerAlarmConfigMigration] Incomplete v2 schema detected (${decoded.length}/5 prayers). Repairing missing prayers...");
          // M3: Incomplete v2 repair without resetting existing valid prayers
          final Map<PrayerId, PrayerAlarmConfigModel> repaired = {};
          for (final id in PrayerId.values) {
            if (decoded.containsKey(id.key)) {
              repaired[id] = PrayerAlarmConfigModel.fromJson(decoded[id.key] as Map<String, dynamic>);
            } else {
              repaired[id] = PrayerAlarmConfigModel(
                prayerId: id,
                alarmType: PrayerAlarmType.alarm,
                audioSource: AudioSourceConfig.defaultBuiltInFallback(isFajr: id == PrayerId.fajr),
                volume: null,
                isVibrationEnabled: null,
              );
            }
          }
          await saveAllConfigs(repaired);
          return true;
        } catch (e) {
          log("⚠️ [PrayerAlarmConfigMigration] Error reading existing v2 JSON during check: $e");
        }
      }
    }

    log("🔄 [PrayerAlarmConfigMigration] Executing migration to v$currentVersion (from v$version)...");

    // Try reading existing v1 JSON if available (M4 / M5)
    Map<String, dynamic>? v1Decoded;
    final String? existingJsonStr = prefs.getString(configsJsonKey);
    if (existingJsonStr != null) {
      try {
        v1Decoded = json.decode(existingJsonStr) as Map<String, dynamic>;
      } catch (e) {
        log("⚠️ [PrayerAlarmConfigMigration] Failed to decode existing configs JSON: $e");
      }
    }

    // Resolve baseline from legacy adhanStyle (M6)
    final String? legacyStyleRaw = prefs.getString(legacyAdhanStyleKey);
    final PrayerAlarmType resolvedLegacyType;
    if (legacyStyleRaw == null) {
      resolvedLegacyType = PrayerAlarmType.alarm;
    } else {
      switch (legacyStyleRaw.toLowerCase().trim()) {
        case 'alarm':
          resolvedLegacyType = PrayerAlarmType.alarm;
          break;
        case 'notification':
          resolvedLegacyType = PrayerAlarmType.notification;
          break;
        case 'none':
          resolvedLegacyType = PrayerAlarmType.off;
          break;
        default:
          resolvedLegacyType = PrayerAlarmType.alarm;
          break;
      }
    }

    // Build v2 configurations for all five prayers
    final Map<PrayerId, PrayerAlarmConfigModel> newConfigs = {};
    for (final id in PrayerId.values) {
      PrayerAlarmType type = resolvedLegacyType;
      AudioSourceConfig audioSource = AudioSourceConfig.defaultBuiltInFallback(isFajr: id == PrayerId.fajr);
      double? volume;
      bool? isVibrationEnabled;

      // 1. If v1 JSON had this prayer, preserve its alarmType (M4/M5)
      if (v1Decoded != null && v1Decoded.containsKey(id.key)) {
        final prayerJson = v1Decoded[id.key];
        if (prayerJson is Map<String, dynamic>) {
          type = PrayerAlarmType.fromKey(prayerJson['alarmType'] as String?, fallback: resolvedLegacyType);
          if (prayerJson['audioSource'] is Map<String, dynamic>) {
            audioSource = AudioSourceConfig.fromJson(
              prayerJson['audioSource'] as Map<String, dynamic>,
              isFajr: id == PrayerId.fajr,
            );
          }
          if (prayerJson['volume'] is num) {
            volume = (prayerJson['volume'] as num).toDouble().clamp(0.1, 1.0);
          }
          if (prayerJson['isVibrationEnabled'] is bool) {
            isVibrationEnabled = prayerJson['isVibrationEnabled'] as bool;
          }
        }
      } else {
        // Fallback: Check individual legacy keys (M7)
        final existingKeyVal = prefs.getString(alarmTypeKey(id.key));
        if (existingKeyVal != null) {
          type = PrayerAlarmType.fromKey(existingKeyVal, fallback: resolvedLegacyType);
        }
        final existingSound = prefs.getString(alarmSoundKey(id.key));
        if (existingSound != null && existingSound.isNotEmpty) {
          if (existingSound == defaultFajrSound) {
            audioSource = AudioSourceConfig.defaultBuiltInFallback(isFajr: true);
          } else if (existingSound == defaultGeneralSound) {
            audioSource = AudioSourceConfig.defaultBuiltInFallback(isFajr: false);
          } else {
            audioSource = BuiltInAudioSource(
              id: 'builtIn:$existingSound',
              displayName: id == PrayerId.fajr ? 'أذان الفجر' : 'الأذان',
              assetPath: existingSound,
            );
          }
        }
      }

      newConfigs[id] = PrayerAlarmConfigModel(
        prayerId: id,
        alarmType: type,
        audioSource: audioSource,
        volume: volume,
        isVibrationEnabled: isVibrationEnabled,
      );
    }

    // Persist new v2 configurations atomically
    await saveAllConfigs(newConfigs);

    // Write version marker only after complete write
    await prefs.setInt(versionKey, currentVersion);
    log("✅ [PrayerAlarmConfigMigration] Migration to v$currentVersion completed successfully!");
    return true;
  }

  @override
  Future<Map<PrayerId, PrayerAlarmConfigModel>> getConfigs() async {
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
      final rawSound = prefs.getString(alarmSoundKey(id.key));
      final audioSource = rawSound != null && rawSound.isNotEmpty
          ? (rawSound == defaultFajrSound
              ? AudioSourceConfig.defaultBuiltInFallback(isFajr: true)
              : (rawSound == defaultGeneralSound
                  ? AudioSourceConfig.defaultBuiltInFallback(isFajr: false)
                  : BuiltInAudioSource(id: 'builtIn:$rawSound', displayName: 'الأذان', assetPath: rawSound)))
          : AudioSourceConfig.defaultBuiltInFallback(isFajr: id == PrayerId.fajr);
      final volume = prefs.getDouble(alarmVolumeKey(id.key));
      final isVibration = prefs.containsKey(alarmVibrationKey(id.key))
          ? prefs.getBool(alarmVibrationKey(id.key))
          : null;

      result[id] = PrayerAlarmConfigModel(
        prayerId: id,
        alarmType: alarmType,
        audioSource: audioSource,
        volume: volume,
        isVibrationEnabled: isVibration,
      );
    }
    return result;
  }

  @override
  Future<PrayerAlarmConfigModel> getConfig(PrayerId prayerId) async {
    final all = await getConfigs();
    return all[prayerId] ??
        PrayerAlarmConfigModel(
          prayerId: prayerId,
          alarmType: PrayerAlarmType.alarm,
          audioSource: AudioSourceConfig.defaultBuiltInFallback(isFajr: prayerId == PrayerId.fajr),
        );
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfigModel config) async {
    final current = await getConfigs();
    current[config.prayerId] = config;
    await saveAllConfigs(current);
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfigModel> configs) async {
    for (final entry in configs.entries) {
      await prefs.setString(alarmTypeKey(entry.key.key), entry.value.alarmType.key);
      if (entry.value.audioSource is BuiltInAudioSource) {
        await prefs.setString(
          alarmSoundKey(entry.key.key),
          (entry.value.audioSource as BuiltInAudioSource).assetPath,
        );
      }
      if (entry.value.volume != null) {
        await prefs.setDouble(alarmVolumeKey(entry.key.key), entry.value.volume!);
      } else {
        await prefs.remove(alarmVolumeKey(entry.key.key));
      }
      if (entry.value.isVibrationEnabled != null) {
        await prefs.setBool(alarmVibrationKey(entry.key.key), entry.value.isVibrationEnabled!);
      } else {
        await prefs.remove(alarmVibrationKey(entry.key.key));
      }
    }
    final jsonMap = configs.map(
      (key, value) => MapEntry(key.key, value.toJson()),
    );
    await prefs.setString(configsJsonKey, json.encode(jsonMap));
  }
}
