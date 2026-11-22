import '../entities/focus_schedule.dart';

/// Calculates the exact next trigger time for a given [FocusSchedule].
class FocusScheduleCalculator {
  /// Calculates the next occurrence strictly after [referenceNow].
  ///
  /// Iterates day by day from today up to 14 days ahead to find the earliest
  /// matching weekday and time strictly greater than [referenceNow].
  DateTime calculateNextTrigger(FocusSchedule schedule, DateTime referenceNow) {
    if (schedule.daysOfWeek.isEmpty) {
      throw ArgumentError('Schedule must define at least one day of the week');
    }

    // Check up to 14 days ahead to cover all weekly combinations and edge cases.
    for (int dayOffset = 0; dayOffset <= 14; dayOffset++) {
      final candidateDate = referenceNow.add(Duration(days: dayOffset));
      final candidateWeekday = candidateDate.weekday;

      if (schedule.daysOfWeek.contains(candidateWeekday)) {
        final candidateTime = DateTime(
          candidateDate.year,
          candidateDate.month,
          candidateDate.day,
          schedule.hour,
          schedule.minute,
        );

        if (candidateTime.isAfter(referenceNow)) {
          return candidateTime;
        }
      }
    }

    // Fallback in case of unexpected calculation loop
    return referenceNow.add(const Duration(days: 1));
  }

  /// Calculates pre-notification time if configured, otherwise null.
  DateTime? calculatePreNotificationTime(
      FocusSchedule schedule, DateTime nextTrigger) {
    if (schedule.preNotificationMinutes <= 0) return null;
    return nextTrigger.subtract(Duration(minutes: schedule.preNotificationMinutes));
  }
}
