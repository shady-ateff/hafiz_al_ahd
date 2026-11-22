import '../entities/focus_schedule.dart';

enum MissedScheduleAction {
  /// The trigger time is in the future.
  upcoming,

  /// The trigger time passed recently (within grace period).
  /// Safe to prompt or activate immediately.
  activateWithinGracePeriod,

  /// The trigger time passed long ago (outside grace period).
  /// Should be skipped and scheduled for the next cycle.
  skipToNextOccurrence,
}

class MissedScheduleResolution {
  final MissedScheduleAction action;
  final Duration? elapsedSinceScheduled;
  final String explanation;

  const MissedScheduleResolution({
    required this.action,
    this.elapsedSinceScheduled,
    required this.explanation,
  });
}

/// Evaluates schedules when the device boots or app launches after scheduled triggers.
class MissedSchedulePolicy {
  final Duration defaultGracePeriod;

  const MissedSchedulePolicy({
    this.defaultGracePeriod = const Duration(minutes: 30),
  });

  /// Evaluates whether a scheduled trigger at [scheduledTime] should be executed
  /// or skipped based on [currentTime].
  MissedScheduleResolution evaluate({
    required FocusSchedule schedule,
    required DateTime scheduledTime,
    required DateTime currentTime,
    Duration? customGracePeriod,
  }) {
    final gracePeriod = customGracePeriod ?? defaultGracePeriod;

    if (currentTime.isBefore(scheduledTime)) {
      return const MissedScheduleResolution(
        action: MissedScheduleAction.upcoming,
        explanation: 'Scheduled time has not yet arrived.',
      );
    }

    final elapsed = currentTime.difference(scheduledTime);

    if (elapsed <= gracePeriod) {
      return MissedScheduleResolution(
        action: MissedScheduleAction.activateWithinGracePeriod,
        elapsedSinceScheduled: elapsed,
        explanation:
            'Scheduled trigger missed by ${elapsed.inMinutes} minutes, within grace period (${gracePeriod.inMinutes}m).',
      );
    } else {
      return MissedScheduleResolution(
        action: MissedScheduleAction.skipToNextOccurrence,
        elapsedSinceScheduled: elapsed,
        explanation:
            'Scheduled trigger missed by ${elapsed.inMinutes} minutes, exceeding grace period (${gracePeriod.inMinutes}m). Skipping.',
      );
    }
  }
}
