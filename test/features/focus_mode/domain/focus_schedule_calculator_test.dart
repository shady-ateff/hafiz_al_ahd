import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_schedule.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_schedule_calculator.dart';

void main() {
  late FocusScheduleCalculator calculator;

  setUp(() {
    calculator = FocusScheduleCalculator();
  });

  group('FocusScheduleCalculator — Next Trigger Calculations', () {
    test('calculates trigger for today when target time is in the future', () {
      final now = DateTime(2026, 11, 22, 6, 0); // Sunday 06:00 AM
      final schedule = FocusSchedule.daily(
        id: 'sched_1',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 30,
        now: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);

      expect(nextTrigger, DateTime(2026, 11, 22, 7, 30));
    });

    test('calculates trigger for tomorrow when target time has passed today', () {
      final now = DateTime(2026, 11, 22, 8, 0); // Sunday 08:00 AM
      final schedule = FocusSchedule.daily(
        id: 'sched_2',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 30,
        now: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);

      expect(nextTrigger, DateTime(2026, 11, 23, 7, 30)); // Monday 07:30 AM
    });

    test('respects specific days of the week', () {
      // 2026-11-22 is Sunday (weekday = 7)
      final now = DateTime(2026, 11, 22, 10, 0);

      // Schedule only on Tuesday (weekday = 2) and Thursday (weekday = 4)
      final schedule = FocusSchedule(
        id: 'sched_tue_thu',
        wardType: FocusWardType.quranReading,
        title: 'ورد القرآن',
        hour: 18,
        minute: 0,
        daysOfWeek: const [DateTime.tuesday, DateTime.thursday],
        createdAt: now,
        updatedAt: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);

      // Earliest upcoming match from Sunday is Tuesday: 2026-11-24
      expect(nextTrigger.weekday, DateTime.tuesday);
      expect(nextTrigger, DateTime(2026, 11, 24, 18, 0));
    });

    test('handles midnight rollover correctly', () {
      final now = DateTime(2026, 11, 22, 23, 45); // 23:45 PM
      final schedule = FocusSchedule.daily(
        id: 'sched_midnight',
        wardType: FocusWardType.custom,
        title: 'أذكار الليل',
        hour: 0,
        minute: 15,
        now: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);

      // Should be next day at 00:15 AM
      expect(nextTrigger, DateTime(2026, 11, 23, 0, 15));
    });

    test('calculates pre-notification time correctly', () {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule(
        id: 'sched_pre',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        daysOfWeek: const [DateTime.sunday],
        preNotificationMinutes: 10,
        createdAt: now,
        updatedAt: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);
      final preNotification =
          calculator.calculatePreNotificationTime(schedule, nextTrigger);

      expect(nextTrigger, DateTime(2026, 11, 22, 7, 0));
      expect(preNotification, DateTime(2026, 11, 22, 6, 50));
    });

    test('returns null for pre-notification when minutes is zero or negative', () {
      final now = DateTime(2026, 11, 22, 6, 0);
      final schedule = FocusSchedule.daily(
        id: 'sched_no_pre',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 7,
        minute: 0,
        preNotificationMinutes: 0,
        now: now,
      );

      final nextTrigger = calculator.calculateNextTrigger(schedule, now);
      final preNotification =
          calculator.calculatePreNotificationTime(schedule, nextTrigger);

      expect(preNotification, isNull);
    });
  });
}
