import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_schedule_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_scheduling_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_schedule_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_schedule.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_schedule_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/missed_schedule_policy.dart';

void main() {
  late FocusScheduleRepositoryImpl repository;
  late InMemoryFocusSchedulingPort schedulingPort;
  late FocusScheduleCoordinator coordinator;

  setUp(() {
    final dataSource = FocusScheduleLocalDataSourceImpl.inMemory();
    repository = FocusScheduleRepositoryImpl(localDataSource: dataSource);
    schedulingPort = InMemoryFocusSchedulingPort();
    coordinator = FocusScheduleCoordinator(
      repository: repository,
      schedulingPort: schedulingPort,
    );
  });

  group('FocusScheduleCoordinator — Scheduling Lifecycle', () {
    test('adding an enabled schedule persists to DB and arms platform alarm', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule.daily(
        id: 'sched_morning',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        now: now,
      );

      final nextTrigger = await coordinator.addOrUpdateSchedule(schedule, referenceNow: now);

      expect(nextTrigger, DateTime(2026, 11, 22, 7, 0));

      final persisted = await repository.getScheduleById('sched_morning');
      expect(persisted, isNotNull);
      expect(persisted!.title, 'أذكار الصباح');

      expect(schedulingPort.scheduledAlarms.containsKey('sched_morning'), isTrue);
      expect(schedulingPort.scheduledAlarms['sched_morning']!.triggerAt,
          DateTime(2026, 11, 22, 7, 0));
    });

    test('adding a disabled schedule persists to DB but cancels platform alarm', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule(
        id: 'sched_disabled',
        wardType: FocusWardType.eveningAzkar,
        title: 'أذكار المساء',
        hour: 17,
        minute: 0,
        daysOfWeek: const [DateTime.sunday],
        isEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      final nextTrigger = await coordinator.addOrUpdateSchedule(schedule, referenceNow: now);

      expect(nextTrigger, isNull);
      final persisted = await repository.getScheduleById('sched_disabled');
      expect(persisted!.isEnabled, isFalse);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_disabled'), isFalse);
    });

    test('disabling an active schedule updates DB and removes alarm', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule.daily(
        id: 'sched_to_disable',
        wardType: FocusWardType.quranReading,
        title: 'ورد القرآن',
        hour: 20,
        minute: 0,
        now: now,
      );

      await coordinator.addOrUpdateSchedule(schedule, referenceNow: now);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_disable'), isTrue);

      await coordinator.disableSchedule('sched_to_disable');

      final persisted = await repository.getScheduleById('sched_to_disable');
      expect(persisted!.isEnabled, isFalse);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_disable'), isFalse);
    });

    test('enabling an inactive schedule updates DB and arms alarm', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule(
        id: 'sched_to_enable',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 8,
        minute: 0,
        daysOfWeek: const [DateTime.sunday],
        isEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveSchedule(schedule);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_enable'), isFalse);

      final nextTrigger = await coordinator.enableSchedule('sched_to_enable', referenceNow: now);

      expect(nextTrigger, DateTime(2026, 11, 22, 8, 0));
      final persisted = await repository.getScheduleById('sched_to_enable');
      expect(persisted!.isEnabled, isTrue);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_enable'), isTrue);
    });

    test('deleting a schedule removes it from DB and cancels alarm', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule.daily(
        id: 'sched_to_delete',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 9,
        minute: 0,
        now: now,
      );

      await coordinator.addOrUpdateSchedule(schedule, referenceNow: now);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_delete'), isTrue);

      await coordinator.deleteSchedule('sched_to_delete');

      final persisted = await repository.getScheduleById('sched_to_delete');
      expect(persisted, isNull);
      expect(schedulingPort.scheduledAlarms.containsKey('sched_to_delete'), isFalse);
    });

    test('syncAllSchedules resynchronizes all enabled schedules with platform', () async {
      final now = DateTime(2026, 11, 22, 6, 0);
      final s1 = FocusSchedule.daily(
        id: 's1',
        wardType: FocusWardType.morningAzkar,
        title: 'صباح',
        hour: 7,
        minute: 0,
        now: now,
      );
      final s2 = FocusSchedule.daily(
        id: 's2',
        wardType: FocusWardType.eveningAzkar,
        title: 'مساء',
        hour: 17,
        minute: 0,
        now: now,
      );

      await repository.saveSchedule(s1);
      await repository.saveSchedule(s2);

      final results = await coordinator.syncAllSchedules(referenceNow: now);

      expect(results.length, 2);
      expect(results['s1'], DateTime(2026, 11, 22, 7, 0));
      expect(results['s2'], DateTime(2026, 11, 22, 17, 0));
      expect(schedulingPort.scheduledAlarms.length, 2);
    });

    test('onScheduleFired records execution and arms next day trigger', () async {
      final firedAt = DateTime(2026, 11, 22, 7, 0);
      final schedule = FocusSchedule.daily(
        id: 'sched_daily_fired',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        now: firedAt,
      );

      await repository.saveSchedule(schedule);

      final nextTrigger = await coordinator.onScheduleFired('sched_daily_fired', firedAt: firedAt);

      // Next occurrence should be tomorrow at 07:00 AM
      expect(nextTrigger, DateTime(2026, 11, 23, 7, 0));

      final persisted = await repository.getScheduleById('sched_daily_fired');
      expect(persisted!.lastTriggeredAt, firedAt);
      expect(schedulingPort.scheduledAlarms['sched_daily_fired']!.triggerAt,
          DateTime(2026, 11, 23, 7, 0));
    });

    test('checkMissedSchedules evaluates missed alarms after device boot', () async {
      final bootNow = DateTime(2026, 11, 22, 7, 20); // Device booted at 07:20 AM
      final schedule = FocusSchedule.daily(
        id: 'sched_missed_test',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        now: DateTime(2026, 11, 22, 6, 0),
      );

      await repository.saveSchedule(schedule);

      final expectedScheduledTimes = {
        'sched_missed_test': DateTime(2026, 11, 22, 7, 0),
      };

      final resolutions = await coordinator.checkMissedSchedules(
        expectedScheduledTimes: expectedScheduledTimes,
        referenceNow: bootNow,
      );

      expect(resolutions.length, 1);
      expect(resolutions.first.key.id, 'sched_missed_test');
      expect(resolutions.first.value.action, MissedScheduleAction.activateWithinGracePeriod);
      expect(resolutions.first.value.elapsedSinceScheduled, const Duration(minutes: 20));
    });
  });
}
