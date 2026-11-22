import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_schedule.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/missed_schedule_policy.dart';

void main() {
  late MissedSchedulePolicy policy;
  late FocusSchedule schedule;

  setUp(() {
    policy = const MissedSchedulePolicy(defaultGracePeriod: Duration(minutes: 30));
    final now = DateTime(2026, 11, 22, 6, 0);
    schedule = FocusSchedule.daily(
      id: 'sched_daily',
      wardType: FocusWardType.morningAzkar,
      title: 'أذكار الصباح',
      hour: 7,
      minute: 0,
      now: now,
    );
  });

  group('MissedSchedulePolicy — Evaluation Rules', () {
    test('returns upcoming when current time is strictly before scheduled time', () {
      final scheduledTime = DateTime(2026, 11, 22, 7, 0);
      final currentTime = DateTime(2026, 11, 22, 6, 45); // 15 mins before

      final resolution = policy.evaluate(
        schedule: schedule,
        scheduledTime: scheduledTime,
        currentTime: currentTime,
      );

      expect(resolution.action, MissedScheduleAction.upcoming);
      expect(resolution.elapsedSinceScheduled, isNull);
    });

    test('returns activateWithinGracePeriod when elapsed is within 30 minutes', () {
      final scheduledTime = DateTime(2026, 11, 22, 7, 0);
      final currentTime = DateTime(2026, 11, 22, 7, 20); // 20 mins late

      final resolution = policy.evaluate(
        schedule: schedule,
        scheduledTime: scheduledTime,
        currentTime: currentTime,
      );

      expect(resolution.action, MissedScheduleAction.activateWithinGracePeriod);
      expect(resolution.elapsedSinceScheduled, const Duration(minutes: 20));
    });

    test('returns activateWithinGracePeriod exactly at 30 minutes edge', () {
      final scheduledTime = DateTime(2026, 11, 22, 7, 0);
      final currentTime = DateTime(2026, 11, 22, 7, 30); // Exactly 30 mins

      final resolution = policy.evaluate(
        schedule: schedule,
        scheduledTime: scheduledTime,
        currentTime: currentTime,
      );

      expect(resolution.action, MissedScheduleAction.activateWithinGracePeriod);
    });

    test('returns skipToNextOccurrence when elapsed exceeds grace period', () {
      final scheduledTime = DateTime(2026, 11, 22, 7, 0);
      final currentTime = DateTime(2026, 11, 22, 7, 45); // 45 mins late

      final resolution = policy.evaluate(
        schedule: schedule,
        scheduledTime: scheduledTime,
        currentTime: currentTime,
      );

      expect(resolution.action, MissedScheduleAction.skipToNextOccurrence);
      expect(resolution.elapsedSinceScheduled, const Duration(minutes: 45));
    });

    test('respects custom grace period when provided', () {
      final scheduledTime = DateTime(2026, 11, 22, 7, 0);
      final currentTime = DateTime(2026, 11, 22, 7, 12); // 12 mins late

      // Custom grace period of only 10 minutes
      final resolution = policy.evaluate(
        schedule: schedule,
        scheduledTime: scheduledTime,
        currentTime: currentTime,
        customGracePeriod: const Duration(minutes: 10),
      );

      expect(resolution.action, MissedScheduleAction.skipToNextOccurrence);
    });
  });
}
