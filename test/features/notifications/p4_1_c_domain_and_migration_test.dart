import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase P4.1-C.1 — Domain Models & Migration v2 Tests', () {
    // -------------------------------------------------------------------------
    // TEST-C-01: AudioSourceConfig serialization & deserialization round-trip
    // -------------------------------------------------------------------------
    test('TEST-C-01: AudioSourceConfig round-trip JSON serialization for built-in and custom', () {
      const builtIn = BuiltInAudioSource(
        id: 'builtIn:custom_muezzin_1',
        displayName: 'مؤذن الحرم المكي',
        assetPath: 'assets/sounds/makkah.mp3',
      );
      final builtInJson = builtIn.toJson();
      expect(builtInJson['type'], equals('builtIn'));
      expect(builtInJson['id'], equals('builtIn:custom_muezzin_1'));

      final builtInDeserialized = AudioSourceConfig.fromJson(builtInJson);
      expect(builtInDeserialized, equals(builtIn));
      expect(builtInDeserialized, isA<BuiltInAudioSource>());

      const custom = CustomAudioSource(
        id: 'custom:uuid-999',
        displayName: 'أذان مسجل خاص',
        localRelativePath: 'adhan_sounds/recorded_1.mp3',
        originalFileName: 'recorded_1.mp3',
        fileSize: 1048576,
      );
      final customJson = custom.toJson();
      expect(customJson['type'], equals('custom'));
      expect(customJson['localRelativePath'], equals('adhan_sounds/recorded_1.mp3'));

      final customDeserialized = AudioSourceConfig.fromJson(customJson);
      expect(customDeserialized, equals(custom));
      expect(customDeserialized, isA<CustomAudioSource>());
    });

    // -------------------------------------------------------------------------
    // TEST-C-02: Unknown AudioSource discriminator or malformed JSON fallback
    // -------------------------------------------------------------------------
    test('TEST-C-02: Unknown discriminator or malformed JSON falls back safely without throwing', () {
      final unknownTypeJson = {
        'type': 'futureStreamingAudio',
        'streamUrl': 'https://example.com/audio.mp3',
      };
      final fallback1 = AudioSourceConfig.fromJson(unknownTypeJson);
      expect(fallback1, isA<BuiltInAudioSource>());
      expect(fallback1.id, equals('builtIn:mishary_alafasy'));

      // Malformed custom JSON missing required fields
      final malformedCustomJson = {
        'type': 'custom',
        'localRelativePath': null, // Missing!
      };
      final fallback2 = AudioSourceConfig.fromJson(malformedCustomJson, isFajr: true);
      expect(fallback2, isA<BuiltInAudioSource>());
      expect(fallback2.id, equals('builtIn:mishary_alafasy'));
      expect((fallback2 as BuiltInAudioSource).resolveAssetPath(isFajr: true),
          equals('assets/sounds/fajr_azan.mp3'));
    });

    // -------------------------------------------------------------------------
    // TEST-C-03: PrayerAlarmConfig.copyWith with clearVibrationOverride
    // -------------------------------------------------------------------------
    test('TEST-C-03: copyWith clearVibrationOverride resets isVibrationEnabled to null', () {
      final configWithOverride = PrayerAlarmConfig(
        prayerId: PrayerId.asr,
        alarmType: PrayerAlarmType.alarm,
        isVibrationEnabled: false, // Per-prayer override
      );
      expect(configWithOverride.isVibrationEnabled, isFalse);

      final resetConfig = configWithOverride.copyWith(clearVibrationOverride: true);
      expect(resetConfig.isVibrationEnabled, isNull);
      expect(resetConfig.prayerId, equals(PrayerId.asr));
      expect(resetConfig.alarmType, equals(PrayerAlarmType.alarm));

      // Standard copyWith without flag preserves existing override
      final updatedVolume = configWithOverride.copyWith(volume: 0.8);
      expect(updatedVolume.isVibrationEnabled, isFalse);
      expect(updatedVolume.volume, equals(0.8));
    });

    // -------------------------------------------------------------------------
    // TEST-C-04: Volume clamping and double typing
    // -------------------------------------------------------------------------
    test('TEST-C-04: Volume clamping strictly enforces 0.1 to 1.0 double range', () {
      final lowVolConfig = PrayerAlarmConfig(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
      ).copyWith(volume: 0.0);
      expect(lowVolConfig.volume, equals(0.1));
      expect(lowVolConfig.volume, isA<double>());

      final negativeVolConfig = PrayerAlarmConfig(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
      ).copyWith(volume: -0.5);
      expect(negativeVolConfig.volume, equals(0.1));

      final highVolConfig = PrayerAlarmConfig(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
      ).copyWith(volume: 1.5);
      expect(highVolConfig.volume, equals(1.0));
      expect(highVolConfig.volume, isA<double>());
    });

    // -------------------------------------------------------------------------
    // TEST-C-05: Idempotent Migration v1 -> v2
    // -------------------------------------------------------------------------
    test('TEST-C-05: Migration v1 -> v2 preserves existing per-prayer selections & writes v2 marker', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Seed v1 state: version = 1, atomic JSON with only prayerId and alarmType
      await prefs.setInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey, 1);
      final v1Payload = {
        'fajr': {'prayerId': 'fajr', 'alarmType': 'alarm'},
        'dhuhr': {'prayerId': 'dhuhr', 'alarmType': 'notification'},
        'asr': {'prayerId': 'asr', 'alarmType': 'off'},
        'maghrib': {'prayerId': 'maghrib', 'alarmType': 'alarm'},
        'isha': {'prayerId': 'isha', 'alarmType': 'notification'},
      };
      await prefs.setString(
        PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey,
        json.encode(v1Payload),
      );

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final migrated = await dataSource.migrateLegacyIfNeeded();
      expect(migrated, isTrue);

      expect(prefs.getInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey), equals(2));

      final configs = await dataSource.getConfigs();
      expect(configs.length, equals(5));

      // Preserved modes
      expect(configs[PrayerId.fajr]!.alarmType, equals(PrayerAlarmType.alarm));
      expect(configs[PrayerId.dhuhr]!.alarmType, equals(PrayerAlarmType.notification));
      expect(configs[PrayerId.asr]!.alarmType, equals(PrayerAlarmType.off));
      expect(configs[PrayerId.maghrib]!.alarmType, equals(PrayerAlarmType.alarm));
      expect(configs[PrayerId.isha]!.alarmType, equals(PrayerAlarmType.notification));

      // Seeded default v2 values (unified Mishary Alafasy)
      expect(configs[PrayerId.fajr]!.audioSource.id, equals('builtIn:mishary_alafasy'));
      expect(configs[PrayerId.dhuhr]!.audioSource.id, equals('builtIn:mishary_alafasy'));
      expect((configs[PrayerId.fajr]!.audioSource as BuiltInAudioSource).resolveAssetPath(isFajr: true),
          equals('assets/sounds/fajr_azan.mp3'));
      expect((configs[PrayerId.dhuhr]!.audioSource as BuiltInAudioSource).resolveAssetPath(isFajr: false),
          equals('assets/sounds/adhan.mp3'));
      expect(configs[PrayerId.fajr]!.volume, isNull);
      expect(configs[PrayerId.fajr]!.isVibrationEnabled, isNull);

      // Subsequent run is idempotent
      final secondRun = await dataSource.migrateLegacyIfNeeded();
      expect(secondRun, isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST-C-06: Migration from legacy adhanStyle (no v1 JSON)
    // -------------------------------------------------------------------------
    test('TEST-C-06: Migration from legacy adhanStyle = notification accurately converts all prayers', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(PrayerAlarmConfigLocalDataSourceImpl.legacyAdhanStyleKey, 'notification');

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final migrated = await dataSource.migrateLegacyIfNeeded();
      expect(migrated, isTrue);

      expect(prefs.getInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey), equals(2));

      final configs = await dataSource.getConfigs();
      for (final id in PrayerId.values) {
        expect(configs[id]!.alarmType, equals(PrayerAlarmType.notification));
      }
    });

    // -------------------------------------------------------------------------
    // TEST-C-45: Future schema version (version > 2) is preserved without downgrade
    // -------------------------------------------------------------------------
    test('TEST-C-45: Future schema version > 2 is preserved without downgrade or overwrite', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey, 3);
      final futurePayload = {'futureKey': 'valuable_user_data_version_3'};
      await prefs.setString(
        PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey,
        json.encode(futurePayload),
      );

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final result = await dataSource.migrateLegacyIfNeeded();
      expect(result, isFalse);

      // Data and version intact
      expect(prefs.getInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey), equals(3));
      expect(
        prefs.getString(PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey),
        contains('valuable_user_data_version_3'),
      );
    });

    // -------------------------------------------------------------------------
    // Incomplete v2 schema repair (M3)
    // -------------------------------------------------------------------------
    test('M3 Incomplete v2 schema repairs missing prayers without resetting existing ones', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey, 2);
      // Only fajr and dhuhr exist
      final incompletePayload = {
        'fajr': {
          'prayerId': 'fajr',
          'alarmType': 'notification',
          'volume': 0.65,
        },
        'dhuhr': {
          'prayerId': 'dhuhr',
          'alarmType': 'off',
          'volume': 0.8,
        },
      };
      await prefs.setString(
        PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey,
        json.encode(incompletePayload),
      );

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final repaired = await dataSource.migrateLegacyIfNeeded();
      expect(repaired, isTrue);

      final configs = await dataSource.getConfigs();
      expect(configs.length, equals(5));

      // Existing prayers preserved with custom settings
      expect(configs[PrayerId.fajr]!.alarmType, equals(PrayerAlarmType.notification));
      expect(configs[PrayerId.fajr]!.volume, equals(0.65));
      expect(configs[PrayerId.dhuhr]!.alarmType, equals(PrayerAlarmType.off));

      // Missing prayers safely seeded
      expect(configs[PrayerId.asr]!.alarmType, equals(PrayerAlarmType.alarm));
      expect(configs[PrayerId.maghrib]!.alarmType, equals(PrayerAlarmType.alarm));
      expect(configs[PrayerId.isha]!.alarmType, equals(PrayerAlarmType.alarm));
    });
  });
}

