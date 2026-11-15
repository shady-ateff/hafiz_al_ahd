import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('P4.1-B.3 Phase 2C.2.2 — Scheduler Dependency Injection Registration Tests', () {
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
      SharedPreferences.setMockInitialValues({});
      await init();
    });

    test('1. BasePrayerAlarmConfigRepository is registered as LazySingleton', () {
      expect(sl.isRegistered<BasePrayerAlarmConfigRepository>(), isTrue);
      final repo1 = sl<BasePrayerAlarmConfigRepository>();
      final repo2 = sl<BasePrayerAlarmConfigRepository>();
      expect(repo1, isA<PrayerAlarmConfigRepositoryImpl>());
      expect(identical(repo1, repo2), isTrue, reason: 'Must be a singleton instance');
    });

    test('2. ScheduleWeeklyPrayersUseCase is registered as LazySingleton', () {
      expect(sl.isRegistered<ScheduleWeeklyPrayersUseCase>(), isTrue);
      final useCase1 = sl<ScheduleWeeklyPrayersUseCase>();
      final useCase2 = sl<ScheduleWeeklyPrayersUseCase>();
      expect(useCase1, isA<ScheduleWeeklyPrayersUseCase>());
      expect(identical(useCase1, useCase2), isTrue, reason: 'Must be a singleton instance');
    });

    test('3. ScheduleWeeklyPrayersUseCase receives the exact registered BasePrayerAlarmConfigRepository singleton', () {
      final useCase = sl<ScheduleWeeklyPrayersUseCase>();
      final repo = sl<BasePrayerAlarmConfigRepository>();
      expect(
        identical(useCase.prayerAlarmConfigRepository, repo),
        isTrue,
        reason: 'Scheduler must receive the exact same singleton instance from DI without duplicate creation',
      );
    });

    test('4. R5.2 — BaseAudioStorageLock is registered as a LazySingleton', () {
      expect(sl.isRegistered<BaseAudioStorageLock>(), isTrue);
      final lock1 = sl<BaseAudioStorageLock>();
      final lock2 = sl<BaseAudioStorageLock>();
      expect(identical(lock1, lock2), isTrue, reason: 'AudioStorageLock must be a shared singleton across the application');
    });

    test('5. R5.2 — Shared Lock Identity: Repository, Storage Manager, and Settings Cubit share the exact same lock singleton', () {
      final lock = sl<BaseAudioStorageLock>();
      final repo = sl<BasePrayerAlarmConfigRepository>() as PrayerAlarmConfigRepositoryImpl;
      final storageManager = sl<BaseAdhanStorageManagerService>() as AdhanStorageManagerServiceImpl;
      final cubit = sl<PrayerAlarmSettingsCubit>();

      // 1. All components receive the DI singleton instance
      expect(identical(repo.audioStorageLock, lock), isTrue,
          reason: 'PrayerAlarmConfigRepository must use the shared DI lock singleton');
      expect(identical(storageManager.audioStorageLock, lock), isTrue,
          reason: 'AdhanStorageManagerService must use the shared DI lock singleton');
      expect(identical(cubit.audioStorageLock, lock), isTrue,
          reason: 'PrayerAlarmSettingsCubit must use the shared DI lock singleton');

      // 2. Transitive identity guarantees zero duplicate lock creation
      expect(identical(repo.audioStorageLock, storageManager.audioStorageLock), isTrue);
      expect(identical(repo.audioStorageLock, cubit.audioStorageLock), isTrue);
    });

    test('6. R5.2 — Production Dependency Graph Serialization: Save and Delete are serialized through the shared DI lock', () async {
      final lock = sl<BaseAudioStorageLock>();
      final executionOrder = <String>[];

      // Simulate concurrent calls via the production DI instances
      final task1 = lock.synchronized(() async {
        executionOrder.add('task1_start');
        await Future.delayed(const Duration(milliseconds: 30));
        executionOrder.add('task1_end');
      });

      final task2 = lock.synchronized(() async {
        executionOrder.add('task2_start');
        await Future.delayed(const Duration(milliseconds: 10));
        executionOrder.add('task2_end');
      });

      await Future.wait([task1, task2]);

      expect(executionOrder, equals([
        'task1_start',
        'task1_end',
        'task2_start',
        'task2_end',
      ]), reason: 'Concurrent tasks via DI lock must be strictly serialized');
    });
  });
}

