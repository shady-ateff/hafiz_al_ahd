import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('P4.1-B.3 Phase 2C.2.2 — Scheduler Dependency Injection Registration Tests', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
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
  });
}

