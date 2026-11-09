// lib/features/notifications/domain/entities/schedule_operation_result.dart

enum ScheduleOperationStatus {
  scheduled,
  skippedPast,
  skippedOff,
  skippedMatching, // Verified L2 matching alert already active
  skippedImminent,
  opposingDecommissionDeferred, // Desired alert verified, opposing alert deferral (ringing/imminent)
  opposingDecommissionFailed, // Desired alert verified, opposing alert cancellation or ledger removal failed
  failed,
}

enum ScheduleEventType {
  prayerAlert,
  iqama,
  postPrayerAzkar,
  morningAzkar,
  eveningAzkar,
}

/// Level 2 verification outcomes for registered alerts.
enum EventVerificationStatus {
  absent,
  matching,
  stale,
  unverifiable,
}

extension EventVerificationStatusX on EventVerificationStatus {
  bool get isMatching => this == EventVerificationStatus.matching;
  bool get isStale => this == EventVerificationStatus.stale;
  bool get isAbsent => this == EventVerificationStatus.absent;
}

/// Typed cancellation outcomes for safety and reconciliation.
enum EventCancellationStatus {
  cancelled,        // Active event successfully removed from plugin registry/queue and verified absent
  alreadyAbsent,    // Event confirmed absent prior to cancellation (idempotent clean)
  deferredImminent, // Cancellation suppressed: actual time within [-15s, +60s]
  deferredRinging,  // Cancellation suppressed: alarm is actively playing audio
  failed,           // Cancellation call threw, record persisted, or storage removal failed
  unverifiable,     // Pre- or post-cancellation query threw, or metadata correlation was broken
}

extension EventCancellationStatusX on EventCancellationStatus {
  bool get isSuccessful =>
      this == EventCancellationStatus.cancelled ||
      this == EventCancellationStatus.alreadyAbsent;

  bool get isDeferred =>
      this == EventCancellationStatus.deferredImminent ||
      this == EventCancellationStatus.deferredRinging;
}

/// Detailed decommissioning diagnostics for 'off' mode reconciliation.
class OffDecommissionDetails {
  final int alarmId;
  final EventCancellationStatus alarmStatus;
  final int notificationId;
  final EventCancellationStatus notificationStatus;

  const OffDecommissionDetails({
    required this.alarmId,
    required this.alarmStatus,
    required this.notificationId,
    required this.notificationStatus,
  });

  bool get isFullyClean =>
      alarmStatus.isSuccessful && notificationStatus.isSuccessful;

  bool get hasFailure =>
      alarmStatus == EventCancellationStatus.failed ||
      alarmStatus == EventCancellationStatus.unverifiable ||
      notificationStatus == EventCancellationStatus.failed ||
      notificationStatus == EventCancellationStatus.unverifiable;

  bool get hasDeferred =>
      alarmStatus.isDeferred || notificationStatus.isDeferred;
}

/// Immutable record of a single event scheduling attempt.
class ScheduleOperationResult {
  final int? eventId;
  final ScheduleEventType eventType;
  final ScheduleOperationStatus status;
  final DateTime scheduledTime;
  final String? failureReason;
  final OffDecommissionDetails? offDetails;

  const ScheduleOperationResult._({
    this.eventId,
    required this.eventType,
    required this.status,
    required this.scheduledTime,
    this.failureReason,
    this.offDetails,
  });

  const ScheduleOperationResult.scheduled({
    required int eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.scheduled,
          scheduledTime: scheduledTime,
        );

  const ScheduleOperationResult.skippedPast({
    int? eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.skippedPast,
          scheduledTime: scheduledTime,
        );

  const ScheduleOperationResult.skippedOff({
    int? eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
    OffDecommissionDetails? offDetails,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.skippedOff,
          scheduledTime: scheduledTime,
          offDetails: offDetails,
        );

  const ScheduleOperationResult.skippedMatching({
    required int eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.skippedMatching,
          scheduledTime: scheduledTime,
        );

  const ScheduleOperationResult.skippedImminent({
    int? eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
    OffDecommissionDetails? offDetails,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.skippedImminent,
          scheduledTime: scheduledTime,
          offDetails: offDetails,
        );

  const ScheduleOperationResult.opposingDecommissionDeferred({
    required int eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
    OffDecommissionDetails? offDetails,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.opposingDecommissionDeferred,
          scheduledTime: scheduledTime,
          offDetails: offDetails,
        );

  const ScheduleOperationResult.opposingDecommissionFailed({
    required int eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
    required String failureReason,
    OffDecommissionDetails? offDetails,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.opposingDecommissionFailed,
          scheduledTime: scheduledTime,
          failureReason: failureReason,
          offDetails: offDetails,
        );

  const ScheduleOperationResult.failed({
    int? eventId,
    required ScheduleEventType eventType,
    required DateTime scheduledTime,
    required String failureReason,
    OffDecommissionDetails? offDetails,
  }) : this._(
          eventId: eventId,
          eventType: eventType,
          status: ScheduleOperationStatus.failed,
          scheduledTime: scheduledTime,
          failureReason: failureReason,
          offDetails: offDetails,
        );

  bool get isTerminal =>
      status == ScheduleOperationStatus.scheduled ||
      status == ScheduleOperationStatus.skippedPast ||
      status == ScheduleOperationStatus.skippedOff ||
      status == ScheduleOperationStatus.skippedMatching;

  bool get satisfiesDayCompleteness => isTerminal;
  bool get isDeferred =>
      status == ScheduleOperationStatus.skippedImminent ||
      status == ScheduleOperationStatus.opposingDecommissionDeferred;
  bool get isFailure =>
      status == ScheduleOperationStatus.failed ||
      status == ScheduleOperationStatus.opposingDecommissionFailed;
}

/// Aggregate evaluation of all required events for a specific calendar date.
class DaySchedulingOutcome {
  final DateTime date;
  final List<ScheduleOperationResult> operations;
  final int expectedOperationsCount;
  final String? dayFailureReason;

  const DaySchedulingOutcome({
    required this.date,
    required this.operations,
    required this.expectedOperationsCount,
    this.dayFailureReason,
  });

  /// Explicit day-level failure factory (e.g. calculation failure, astronomical anomaly)
  /// without fabricating fake event IDs.
  factory DaySchedulingOutcome.calculationFailure({
    required DateTime date,
    required String reason,
  }) {
    return DaySchedulingOutcome(
      date: date,
      operations: const [],
      expectedOperationsCount: 1,
      dayFailureReason: reason,
    );
  }

  int get attemptedOperationsCount => operations.length;

  /// Derived invariant: Day is complete IF AND ONLY IF there is no dayFailureReason,
  /// all expected operations were attempted, and EVERY operation satisfies day completeness.
  bool get isComplete =>
      dayFailureReason == null &&
      attemptedOperationsCount >= expectedOperationsCount &&
      operations.every((op) => op.satisfiesDayCompleteness);

  ScheduleOperationResult? get firstFailure {
    for (final op in operations) {
      if (op.isFailure) return op;
    }
    return null;
  }

  ScheduleOperationResult? get firstDeferredOperation {
    for (final op in operations) {
      if (op.isDeferred) return op;
    }
    return null;
  }
}
