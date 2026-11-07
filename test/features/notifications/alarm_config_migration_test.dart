import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';

/// Pre-Migration Specification & Contract for Phase 1.2 & Phase 3 Verification
class PrayerAlarmConfigMigrationContract {
  static const String versionKey = PrayerAlarmConfigLocalDataSourceImpl.versionKey;
  static const int targetVersion = PrayerAlarmConfigLocalDataSourceImpl.currentVersion;

  static const String legacyAdhanStyleKey = PrayerAlarmConfigLocalDataSourceImpl.legacyAdhanStyleKey;
  static const String legacyVolumeKey = 'adhan_volume';
  static const String legacyVibrationKey = 'isAdhanVibrationEnabled';

  static const List<String> prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  static String alarmTypeKey(String prayer) => PrayerAlarmConfigLocalDataSourceImpl.alarmTypeKey(prayer);
  static String alarmSoundKey(String prayer) => PrayerAlarmConfigLocalDataSourceImpl.alarmSoundKey(prayer);

  /// Executes the production migration via [PrayerAlarmConfigLocalDataSourceImpl].
  static Future<bool> executeMigration(SharedPreferences prefs) async {
    final dataSource = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
    return await dataSource.migrateLegacyIfNeeded();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('P4.1-B — Migration Test Suite (Pre-Implementation Contract)', () {
    // ------------------------------------------------------------------------
    // Core Migration Mapping Tests
    // ------------------------------------------------------------------------
    test('Migration Mapping: adhanStyle = alarm maps all 5 prayers to alarm', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final prayer in PrayerAlarmConfigMigrationContract.prayers) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(prayer)),
          equals('alarm'),
          reason: '$prayer must be mapped to alarm',
        );
      }
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );
    });

    test('Migration Mapping: adhanStyle = notification maps all 5 prayers to notification', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'notification');

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final prayer in PrayerAlarmConfigMigrationContract.prayers) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(prayer)),
          equals('notification'),
          reason: '$prayer must be mapped to notification',
        );
      }
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );
    });

    test('Migration Mapping: adhanStyle = none maps all 5 prayers to off', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'none');

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final prayer in PrayerAlarmConfigMigrationContract.prayers) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(prayer)),
          equals('off'),
          reason: '$prayer must be mapped to off',
        );
      }
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );
    });

    test('Migration Mapping: missing adhanStyle preserves legacy default (alarm for all 5 prayers)', () async {
      // No adhanStyle set
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final prayer in PrayerAlarmConfigMigrationContract.prayers) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(prayer)),
          equals('alarm'),
        );
      }
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );
    });

    // ------------------------------------------------------------------------
    // 13 Additional Migration Tests Required by Specification
    // ------------------------------------------------------------------------
    test('1. Existing users are migrated exactly once (version marker written)', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');

      final firstRun = await PrayerAlarmConfigMigrationContract.executeMigration(prefs);
      expect(firstRun, isTrue);
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );

      final secondRun = await PrayerAlarmConfigMigrationContract.executeMigration(prefs);
      expect(secondRun, isFalse, reason: 'Second migration run must be a no-op');
    });

    test('2. All five prayer configurations are created', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final p in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']) {
        expect(prefs.containsKey(PrayerAlarmConfigMigrationContract.alarmTypeKey(p)), isTrue);
      }
    });

    test('3. Fajr retains its dedicated default Adhan sound', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(
        prefs.getString(PrayerAlarmConfigMigrationContract.alarmSoundKey('fajr')),
        equals('assets/sounds/fajr_azan.mp3'),
      );
    });

    test('4. Other prayers retain existing general Adhan sound', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final p in ['dhuhr', 'asr', 'maghrib', 'isha']) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmSoundKey(p)),
          equals('assets/sounds/adhan.mp3'),
        );
      }
    });

    test('5. Global volume preference is preserved', () async {
      await prefs.setDouble(PrayerAlarmConfigMigrationContract.legacyVolumeKey, 0.72);
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(prefs.getDouble(PrayerAlarmConfigMigrationContract.legacyVolumeKey), equals(0.72));
    });

    test('6. Global vibration preference is preserved', () async {
      await prefs.setBool(PrayerAlarmConfigMigrationContract.legacyVibrationKey, false);
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(prefs.getBool(PrayerAlarmConfigMigrationContract.legacyVibrationKey), isFalse);
    });

    test('7. Existing prayer calculation preferences remain untouched', () async {
      await prefs.setString('calculation_method', '5');
      await prefs.setString('madhab', 'hanafi');
      await prefs.setDouble('custom_fajr_angle', 19.5);
      await prefs.setDouble('custom_isha_angle', 17.5);

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(prefs.getString('calculation_method'), equals('5'));
      expect(prefs.getString('madhab'), equals('hanafi'));
      expect(prefs.getDouble('custom_fajr_angle'), equals(19.5));
      expect(prefs.getDouble('custom_isha_angle'), equals(17.5));
    });

    test('8. Existing prayer offset preferences remain untouched', () async {
      await prefs.setInt('prayer_offset_fajr', 2);
      await prefs.setInt('prayer_offset_dhuhr', -3);
      await prefs.setInt('prayer_offset_asr', 1);
      await prefs.setInt('prayer_offset_maghrib', 4);
      await prefs.setInt('prayer_offset_isha', -1);

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(prefs.getInt('prayer_offset_fajr'), equals(2));
      expect(prefs.getInt('prayer_offset_dhuhr'), equals(-3));
      expect(prefs.getInt('prayer_offset_asr'), equals(1));
      expect(prefs.getInt('prayer_offset_maghrib'), equals(4));
      expect(prefs.getInt('prayer_offset_isha'), equals(-1));
    });

    test('9. Re-running migration does not overwrite user-modified configurations', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      // User subsequently modifies Fajr to off and Asr to notification
      await prefs.setString(PrayerAlarmConfigMigrationContract.alarmTypeKey('fajr'), 'off');
      await prefs.setString(PrayerAlarmConfigMigrationContract.alarmTypeKey('asr'), 'notification');

      // Re-run migration
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      expect(prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey('fajr')), equals('off'));
      expect(prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey('asr')), equals('notification'));
      expect(prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey('dhuhr')), equals('alarm'));
    });

    test('10. Partially completed migration can recover safely', () async {
      // Simulate partial migration crash: some keys written but versionKey not written
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await prefs.setString(PrayerAlarmConfigMigrationContract.alarmTypeKey('fajr'), 'alarm');
      // versionKey is missing!

      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      // Must complete remaining keys and write version key
      for (final p in PrayerAlarmConfigMigrationContract.prayers) {
        expect(prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(p)), equals('alarm'));
      }
      expect(
        prefs.getInt(PrayerAlarmConfigMigrationContract.versionKey),
        equals(PrayerAlarmConfigMigrationContract.targetVersion),
      );
    });

    test('11. Missing or malformed legacy values are handled deterministically', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'unrecognized_value_123');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      // Safe fallback must be alarm
      for (final p in PrayerAlarmConfigMigrationContract.prayers) {
        expect(prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(p)), equals('alarm'));
      }
    });

    test('12. Migration does not delete legacy keys in Phase 3', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      // Per rule: "Do not remove legacy preferences until migration is verified."
      expect(prefs.containsKey(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey), isTrue);
    });

    test('13. Migration does not silently disable alarms for existing users', () async {
      await prefs.setString(PrayerAlarmConfigMigrationContract.legacyAdhanStyleKey, 'alarm');
      await PrayerAlarmConfigMigrationContract.executeMigration(prefs);

      for (final p in PrayerAlarmConfigMigrationContract.prayers) {
        expect(
          prefs.getString(PrayerAlarmConfigMigrationContract.alarmTypeKey(p)),
          isNot(equals('off')),
          reason: 'Alarms must not be silently disabled',
        );
      }
    });
  });
}

