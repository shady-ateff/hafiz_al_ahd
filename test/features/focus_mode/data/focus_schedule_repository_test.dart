import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_schedule_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_schedule_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_schedule.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';

void main() {
  late FocusScheduleRepositoryImpl repository;
  late FocusScheduleLocalDataSourceImpl dataSource;

  setUp(() {
    dataSource = FocusScheduleLocalDataSourceImpl.inMemory();
    repository = FocusScheduleRepositoryImpl(localDataSource: dataSource);
  });

  group('FocusScheduleRepository — SQLite & Model Persistence', () {
    test('saveSchedule persists schedule with QuranReadingGoal snapshot', () async {
      final now = DateTime(2026, 11, 22, 10, 0);
      final quranGoal = QuranReadingGoal.pageCount(5);
      final schedule = FocusSchedule(
        id: 'sched_quran_1',
        wardType: FocusWardType.quranReading,
        title: 'قراءة 5 صفحات',
        hour: 14,
        minute: 30,
        daysOfWeek: const [1, 2, 3, 4, 5],
        isEnabled: true,
        preNotificationMinutes: 5,
        targetQuranGoal: quranGoal,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveSchedule(schedule);

      final retrieved = await repository.getScheduleById('sched_quran_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'sched_quran_1');
      expect(retrieved.wardType, FocusWardType.quranReading);
      expect(retrieved.hour, 14);
      expect(retrieved.minute, 30);
      expect(retrieved.daysOfWeek, [1, 2, 3, 4, 5]);
      expect(retrieved.preNotificationMinutes, 5);
      expect(retrieved.targetQuranGoal, isNotNull);
      expect(retrieved.targetQuranGoal!.targetValue, 5);
      expect(retrieved.targetQuranGoal!.goalType, QuranGoalType.pages);
    });

    test('getEnabledSchedules filters out disabled schedules', () async {
      final now = DateTime(2026, 11, 22, 10, 0);
      final sEnabled = FocusSchedule.daily(
        id: 's_en',
        wardType: FocusWardType.morningAzkar,
        title: 'مفعل',
        hour: 7,
        minute: 0,
        now: now,
      );
      final sDisabled = FocusSchedule(
        id: 's_dis',
        wardType: FocusWardType.eveningAzkar,
        title: 'معطل',
        hour: 18,
        minute: 0,
        daysOfWeek: const [1],
        isEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveSchedule(sEnabled);
      await repository.saveSchedule(sDisabled);

      final all = await repository.getAllSchedules();
      expect(all.length, 2);

      final enabledOnly = await repository.getEnabledSchedules();
      expect(enabledOnly.length, 1);
      expect(enabledOnly.first.id, 's_en');
    });

    test('updateScheduleStatus modifies enabled status in place', () async {
      final now = DateTime(2026, 11, 22, 10, 0);
      final schedule = FocusSchedule.daily(
        id: 's_toggle',
        wardType: FocusWardType.custom,
        title: 'ورد مخصص',
        hour: 23,
        minute: 0,
        now: now,
      );

      await repository.saveSchedule(schedule);
      expect((await repository.getScheduleById('s_toggle'))!.isEnabled, isTrue);

      await repository.updateScheduleStatus('s_toggle', false);
      expect((await repository.getScheduleById('s_toggle'))!.isEnabled, isFalse);

      await repository.updateScheduleStatus('s_toggle', true);
      expect((await repository.getScheduleById('s_toggle'))!.isEnabled, isTrue);
    });

    test('recordTrigger updates lastTriggeredAt timestamp', () async {
      final now = DateTime(2026, 11, 22, 10, 0);
      final schedule = FocusSchedule.daily(
        id: 's_trigger',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        now: now,
      );

      await repository.saveSchedule(schedule);
      expect((await repository.getScheduleById('s_trigger'))!.lastTriggeredAt, isNull);

      final triggerTime = DateTime(2026, 11, 22, 7, 0);
      await repository.recordTrigger('s_trigger', triggerTime);

      final updated = await repository.getScheduleById('s_trigger');
      expect(updated!.lastTriggeredAt, triggerTime);
    });

    test('deleteSchedule completely removes entry', () async {
      final now = DateTime(2026, 11, 22, 10, 0);
      final schedule = FocusSchedule.daily(
        id: 's_del',
        wardType: FocusWardType.morningAzkar,
        title: 'حذف',
        hour: 6,
        minute: 0,
        now: now,
      );

      await repository.saveSchedule(schedule);
      expect(await repository.getScheduleById('s_del'), isNotNull);

      await repository.deleteSchedule('s_del');
      expect(await repository.getScheduleById('s_del'), isNull);
    });
  });
}
