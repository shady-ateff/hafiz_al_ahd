import '../entities/focus_schedule.dart';
import '../ports/focus_scheduling_port.dart';
import '../repositories/focus_schedule_repository.dart';
import 'focus_schedule_calculator.dart';
import 'missed_schedule_policy.dart';

/// Coordinates scheduling lifecycle between domain logic, repository, and platform port.
class FocusScheduleCoordinator {
  final FocusScheduleRepository _repository;
  final FocusSchedulingPort _schedulingPort;
  final FocusScheduleCalculator _calculator;
  final MissedSchedulePolicy _missedPolicy;

  FocusScheduleCoordinator({
    required FocusScheduleRepository repository,
    required FocusSchedulingPort schedulingPort,
    FocusScheduleCalculator? calculator,
    MissedSchedulePolicy? missedPolicy,
  })  : _repository = repository,
        _schedulingPort = schedulingPort,
        _calculator = calculator ?? FocusScheduleCalculator(),
        _missedPolicy = missedPolicy ?? const MissedSchedulePolicy();

  /// Adds or updates a schedule, automatically arming the platform alarm if enabled.
  Future<DateTime?> addOrUpdateSchedule(FocusSchedule schedule,
      {DateTime? referenceNow}) async {
    final now = referenceNow ?? DateTime.now();
    await _repository.saveSchedule(schedule);

    if (schedule.isEnabled) {
      final nextTrigger = _calculator.calculateNextTrigger(schedule, now);
      await _schedulingPort.scheduleAlarm(
        scheduleId: schedule.id,
        triggerAt: nextTrigger,
        wardTitle: schedule.title,
        wardType: schedule.wardType,
      );
      return nextTrigger;
    } else {
      await _schedulingPort.cancelAlarm(schedule.id);
      return null;
    }
  }

  /// Disables an existing schedule and cancels its platform alarm.
  Future<void> disableSchedule(String scheduleId) async {
    await _repository.updateScheduleStatus(scheduleId, false);
    await _schedulingPort.cancelAlarm(scheduleId);
  }

  /// Enables an existing schedule and arms its platform alarm.
  Future<DateTime?> enableSchedule(String scheduleId,
      {DateTime? referenceNow}) async {
    final now = referenceNow ?? DateTime.now();
    final schedule = await _repository.getScheduleById(scheduleId);
    if (schedule == null) return null;

    await _repository.updateScheduleStatus(scheduleId, true);
    final enabledSchedule = schedule.copyWith(isEnabled: true);
    final nextTrigger = _calculator.calculateNextTrigger(enabledSchedule, now);

    await _schedulingPort.scheduleAlarm(
      scheduleId: schedule.id,
      triggerAt: nextTrigger,
      wardTitle: schedule.title,
      wardType: schedule.wardType,
    );

    return nextTrigger;
  }

  /// Deletes a schedule completely and cancels its platform alarm.
  Future<void> deleteSchedule(String scheduleId) async {
    await _schedulingPort.cancelAlarm(scheduleId);
    await _repository.deleteSchedule(scheduleId);
  }

  /// Cancels all active platform alarms across all schedules (e.g. when master switch is disabled).
  Future<void> cancelAllSchedules() async {
    final allSchedules = await _repository.getAllSchedules();
    for (final schedule in allSchedules) {
      await _schedulingPort.cancelAlarm(schedule.id);
    }
  }

  /// Resynchronizes all enabled schedules with the platform (e.g. upon app launch or time sync).
  Future<Map<String, DateTime>> syncAllSchedules({DateTime? referenceNow}) async {
    final now = referenceNow ?? DateTime.now();
    final enabledSchedules = await _repository.getEnabledSchedules();
    final results = <String, DateTime>{};

    for (final schedule in enabledSchedules) {
      final nextTrigger = _calculator.calculateNextTrigger(schedule, now);
      await _schedulingPort.scheduleAlarm(
        scheduleId: schedule.id,
        triggerAt: nextTrigger,
        wardTitle: schedule.title,
        wardType: schedule.wardType,
      );
      results[schedule.id] = nextTrigger;
    }

    return results;
  }

  /// Called when a schedule triggers, recording execution and arming the next occurrence.
  Future<DateTime?> onScheduleFired(String scheduleId,
      {DateTime? firedAt}) async {
    final now = firedAt ?? DateTime.now();
    await _repository.recordTrigger(scheduleId, now);

    final schedule = await _repository.getScheduleById(scheduleId);
    if (schedule != null && schedule.isEnabled) {
      final nextTrigger = _calculator.calculateNextTrigger(schedule, now);
      await _schedulingPort.scheduleAlarm(
        scheduleId: schedule.id,
        triggerAt: nextTrigger,
        wardTitle: schedule.title,
        wardType: schedule.wardType,
      );
      return nextTrigger;
    }
    return null;
  }

  /// Evaluates whether any enabled schedules were missed during device shutdown.
  Future<List<MapEntry<FocusSchedule, MissedScheduleResolution>>>
      checkMissedSchedules({
    required Map<String, DateTime> expectedScheduledTimes,
    DateTime? referenceNow,
  }) async {
    final now = referenceNow ?? DateTime.now();
    final enabledSchedules = await _repository.getEnabledSchedules();
    final resolutions =
        <MapEntry<FocusSchedule, MissedScheduleResolution>>[];

    for (final schedule in enabledSchedules) {
      final scheduledTime = expectedScheduledTimes[schedule.id];
      if (scheduledTime != null) {
        final resolution = _missedPolicy.evaluate(
          schedule: schedule,
          scheduledTime: scheduledTime,
          currentTime: now,
        );
        resolutions.add(MapEntry(schedule, resolution));
      }
    }

    return resolutions;
  }
}
