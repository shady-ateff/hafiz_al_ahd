import '../../domain/entities/focus_ward_type.dart';
import '../../domain/ports/focus_scheduling_port.dart';

class ScheduledAlarmEntry {
  final String scheduleId;
  final DateTime triggerAt;
  final String wardTitle;
  final FocusWardType wardType;

  ScheduledAlarmEntry({
    required this.scheduleId,
    required this.triggerAt,
    required this.wardTitle,
    required this.wardType,
  });
}

/// In-memory mock for [FocusSchedulingPort] used for hermetic tests.
class InMemoryFocusSchedulingPort implements FocusSchedulingPort {
  final Map<String, ScheduledAlarmEntry> scheduledAlarms = {};
  bool canScheduleExact = true;
  int requestPermissionCallCount = 0;

  @override
  Future<bool> scheduleAlarm({
    required String scheduleId,
    required DateTime triggerAt,
    required String wardTitle,
    required FocusWardType wardType,
  }) async {
    scheduledAlarms[scheduleId] = ScheduledAlarmEntry(
      scheduleId: scheduleId,
      triggerAt: triggerAt,
      wardTitle: wardTitle,
      wardType: wardType,
    );
    return true;
  }

  @override
  Future<bool> cancelAlarm(String scheduleId) async {
    final removed = scheduledAlarms.remove(scheduleId);
    return removed != null;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    return canScheduleExact;
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    requestPermissionCallCount++;
  }
}
