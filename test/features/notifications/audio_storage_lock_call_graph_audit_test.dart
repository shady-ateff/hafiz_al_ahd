import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  group('R5.7 — Production Call-Graph Audit & Zero Nested Lock Acquisition Verification', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (MethodCall methodCall) async => 1,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (MethodCall methodCall) async => 1,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => Directory.systemTemp.path,
      );
      SharedPreferences.setMockInitialValues({});
      await init();
    });

    test('1. Static Code Analysis: Exactly 5 lock acquisition sites exist in lib/', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final synchronizedSites = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('.synchronized(')) {
            final relPath = p.relative(file.path, from: Directory.current.path).replaceAll('\\', '/');
            synchronizedSites.add('$relPath:${i + 1}');
          }
        }
      }

      // Assert exactly 5 sites exist across production code:
      // 1. PrayerAlarmConfigRepositoryImpl.saveConfig
      // 2. PrayerAlarmConfigRepositoryImpl.saveAllConfigs
      // 3. PrayerAlarmConfigRepositoryImpl.migrateLegacyConfigsIfNeeded
      // 4. AdhanStorageManagerServiceImpl.deleteAudioFile
      // 5. PrayerAlarmSettingsCubit.updateGlobalAudioSource
      expect(synchronizedSites.length, equals(5),
          reason: 'Only the 5 authorized write and delete paths may acquire AudioStorageLock');

      expect(
        synchronizedSites.any((s) => s.contains('prayer_alarm_config_repository_impl.dart')),
        isTrue,
      );
      expect(
        synchronizedSites.any((s) => s.contains('adhan_storage_manager_service_impl.dart')),
        isTrue,
      );
      expect(
        synchronizedSites.any((s) => s.contains('prayer_alarm_settings_cubit.dart')),
        isTrue,
      );
    });

    test('2. Runtime Audit: Sequential execution of all 5 lock sites completes without deadlock', () async {
      final lock = sl<BaseAudioStorageLock>();
      final repo = sl<BasePrayerAlarmConfigRepository>() as PrayerAlarmConfigRepositoryImpl;
      final storageManager = sl<BaseAdhanStorageManagerService>() as AdhanStorageManagerServiceImpl;
      final cubit = sl<PrayerAlarmSettingsCubit>();

      // 1. saveConfig
      await repo.saveConfig(const PrayerAlarmConfig(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: BuiltInAudioSource(id: 'builtIn:default', displayName: 'Default', assetPath: 'assets/sounds/adhan.mp3'),
      ));
      expect(lock.isLocked, isFalse);

      // 2. saveAllConfigs
      await repo.saveAllConfigs({
        for (final id in PrayerId.values)
          id: PrayerAlarmConfig(
            prayerId: id,
            alarmType: PrayerAlarmType.alarm,
            audioSource: const BuiltInAudioSource(id: 'builtIn:default', displayName: 'Default', assetPath: 'assets/sounds/adhan.mp3'),
          ),
      });
      expect(lock.isLocked, isFalse);

      // 3. migrateLegacyConfigsIfNeeded
      final migrated = await repo.migrateLegacyConfigsIfNeeded();
      expect(migrated, isA<bool>());
      expect(lock.isLocked, isFalse);

      // 4. deleteAudioFile (non-existent file returns Left without deadlocking)
      final deleteResult = await storageManager.deleteAudioFile('adhan_sounds/non_existent.mp3');
      expect(deleteResult.isLeft(), isTrue);
      expect(lock.isLocked, isFalse);

      // 5. updateGlobalAudioSource
      final globalUpdated = await cubit.updateGlobalAudioSource(
        const BuiltInAudioSource(id: 'builtIn:global_test', displayName: 'Global Test', assetPath: 'assets/sounds/adhan.mp3'),
      );
      expect(globalUpdated, isTrue);
      expect(lock.isLocked, isFalse);
    });

    test('3. Caller Audit: Direct invocation of saveConfig through Settings Cubit does not create nested lock', () async {
      final cubit = sl<PrayerAlarmSettingsCubit>();
      final lock = sl<BaseAudioStorageLock>();

      await cubit.loadSettings();

      // Cubit calls configRepository.saveConfig directly without holding the lock itself
      final success = await cubit.updatePrayerAudioSource(
        PrayerId.dhuhr,
        const BuiltInAudioSource(id: 'builtIn:dhuhr_sound', displayName: 'Dhuhr Sound', assetPath: 'assets/sounds/adhan.mp3'),
      );

      expect(success, isTrue);
      expect(lock.isLocked, isFalse);
    });
  });
}
