import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('P4.1-B.2 — Crash-Recovery & Persistence Fault Injection Tests', () {
    test('Simulated crash before writing configuration payload: next launch recovers cleanly', () async {
      // Setup legacy preference
      await prefs.setString(PrayerAlarmConfigLocalDataSourceImpl.legacyAdhanStyleKey, 'notification');

      // State: 0 configs written, 0 marker written.
      // Next launch triggers migration:
      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final migrated = await dataSource.migrateLegacyIfNeeded();

      expect(migrated, isTrue);
      expect(await dataSource.getVersion(), equals(PrayerAlarmConfigLocalDataSourceImpl.currentVersion));

      final configs = await dataSource.getConfigs();
      expect(configs.length, equals(5));
      for (final id in PrayerId.values) {
        expect(configs[id]?.alarmType, equals(PrayerAlarmType.notification));
      }
    });

    test('Simulated crash after writing payload but before version marker: next launch completes recovery', () async {
      await prefs.setString(PrayerAlarmConfigLocalDataSourceImpl.legacyAdhanStyleKey, 'alarm');

      // Inject partial crash state:
      // Some keys and atomic JSON written, but versionKey is NULL (process killed before writing marker)
      final partialConfigs = {
        'fajr': {'prayerId': 'fajr', 'alarmType': 'alarm'},
        'dhuhr': {'prayerId': 'dhuhr', 'alarmType': 'alarm'},
      };
      await prefs.setString(
        PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey,
        json.encode(partialConfigs),
      );
      await prefs.setString('prayer_alarm_type_fajr', 'alarm');
      // Notice: 'prayer_alarm_config_version' is deliberately left unset!

      expect(prefs.getInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey), isNull);

      // Launch application / data source recovery
      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final migrated = await dataSource.migrateLegacyIfNeeded();

      expect(migrated, isTrue);
      // Version marker must now be written
      expect(await dataSource.getVersion(), equals(PrayerAlarmConfigLocalDataSourceImpl.currentVersion));

      // All 5 prayers must be fully present and valid
      final configs = await dataSource.getConfigs();
      expect(configs.length, equals(5));
      for (final id in PrayerId.values) {
        expect(configs[id], isNotNull);
        expect(configs[id]!.alarmType, equals(PrayerAlarmType.alarm));
      }
    });

    test('Post-marker idempotency: subsequent calls do not touch user modifications', () async {
      await prefs.setString(PrayerAlarmConfigLocalDataSourceImpl.legacyAdhanStyleKey, 'alarm');

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      await dataSource.migrateLegacyIfNeeded();

      // User customizes Fajr to off and Asr to notification
      await dataSource.saveConfig(
        const PrayerAlarmConfigModel(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off),
      );
      await dataSource.saveConfig(
        const PrayerAlarmConfigModel(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.notification),
      );

      // Simulate app restart and repeated migration invocation
      final restartedDataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final secondMigration = await restartedDataSource.migrateLegacyIfNeeded();

      expect(secondMigration, isFalse, reason: 'Already migrated, must not re-run migration');

      final currentConfigs = await restartedDataSource.getConfigs();
      expect(currentConfigs[PrayerId.fajr]?.alarmType, equals(PrayerAlarmType.off));
      expect(currentConfigs[PrayerId.asr]?.alarmType, equals(PrayerAlarmType.notification));
      expect(currentConfigs[PrayerId.dhuhr]?.alarmType, equals(PrayerAlarmType.alarm));
    });

    test('Recovery from corrupted JSON payload: gracefully falls back to multi-key persistence', () async {
      // Set individual keys properly
      await prefs.setString('prayer_alarm_type_fajr', 'alarm');
      await prefs.setString('prayer_alarm_type_dhuhr', 'notification');
      await prefs.setString('prayer_alarm_type_asr', 'off');
      await prefs.setString('prayer_alarm_type_maghrib', 'alarm');
      await prefs.setString('prayer_alarm_type_isha', 'alarm');
      await prefs.setInt(PrayerAlarmConfigLocalDataSourceImpl.versionKey, PrayerAlarmConfigLocalDataSourceImpl.currentVersion);

      // Corrupt the atomic JSON key with garbage syntax
      await prefs.setString(
        PrayerAlarmConfigLocalDataSourceImpl.configsJsonKey,
        '{corrupted_json_syntax: true, missing_quotes}',
      );

      final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final configs = await dataSource.getConfigs();

      // Must read from individual keys without throwing
      expect(configs.length, equals(5));
      expect(configs[PrayerId.fajr]?.alarmType, equals(PrayerAlarmType.alarm));
      expect(configs[PrayerId.dhuhr]?.alarmType, equals(PrayerAlarmType.notification));
      expect(configs[PrayerId.asr]?.alarmType, equals(PrayerAlarmType.off));
    });

    test('Serialization and Deserialization fidelity (Entity & Model)', () {
      const original = PrayerAlarmConfigModel(
        prayerId: PrayerId.maghrib,
        alarmType: PrayerAlarmType.notification,
      );

      final jsonMap = original.toJson();
      expect(jsonMap['prayerId'], equals('maghrib'));
      expect(jsonMap['alarmType'], equals('notification'));

      final restored = PrayerAlarmConfigModel.fromJson(jsonMap);
      expect(restored.prayerId, equals(PrayerId.maghrib));
      expect(restored.alarmType, equals(PrayerAlarmType.notification));
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));

      // copyWith
      final updated = original.copyWith(alarmType: PrayerAlarmType.off);
      expect(updated.alarmType, equals(PrayerAlarmType.off));
      expect(updated.prayerId, equals(PrayerId.maghrib));
    });
  });
}

