import '../entities/focus_ward_type.dart';

/// Abstract port for scheduling alarms on the native platform.
/// Keeps domain decoupled from Android AlarmManager / WorkManager.
abstract class FocusSchedulingPort {
  /// Schedules an exact alarm on the platform.
  Future<bool> scheduleAlarm({
    required String scheduleId,
    required DateTime triggerAt,
    required String wardTitle,
    required FocusWardType wardType,
  });

  /// Cancels an existing scheduled alarm by scheduleId.
  Future<bool> cancelAlarm(String scheduleId);

  /// Checks if the application currently has permission to schedule exact alarms.
  Future<bool> canScheduleExactAlarms();

  /// Requests or navigates the user to the exact alarm permission settings.
  Future<void> requestExactAlarmPermission();
}
