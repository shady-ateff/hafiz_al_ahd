import '../entities/focus_schedule.dart';

/// Repository interface for persistent storage and retrieval of focus schedules.
abstract class FocusScheduleRepository {
  /// Saves or updates a schedule.
  Future<void> saveSchedule(FocusSchedule schedule);

  /// Retrieves a schedule by its unique ID.
  Future<FocusSchedule?> getScheduleById(String id);

  /// Retrieves all schedules.
  Future<List<FocusSchedule>> getAllSchedules();

  /// Retrieves only schedules that are currently enabled.
  Future<List<FocusSchedule>> getEnabledSchedules();

  /// Deletes a schedule by its ID.
  Future<void> deleteSchedule(String id);

  /// Toggles or updates the enabled status of a schedule.
  Future<void> updateScheduleStatus(String id, bool isEnabled);

  /// Records the timestamp when a schedule was last triggered.
  Future<void> recordTrigger(String id, DateTime triggeredAt);
}
