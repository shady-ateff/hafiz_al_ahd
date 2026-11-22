import 'focus_session_status.dart';
import 'focus_ward_type.dart';
import 'quran_reading_goal.dart';

/// Full domain state representing a Focus Mode session.
class FocusSessionState {
  final String sessionId;
  final FocusWardType wardType;
  final FocusSessionStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final int snoozeCount;
  final int maxSnoozeCount;
  final QuranReadingGoal? quranGoal;
  final String? interruptionReason;
  final bool enforcementStopFailed;

  const FocusSessionState({
    required this.sessionId,
    required this.wardType,
    required this.status,
    required this.startTime,
    this.endTime,
    this.snoozeCount = 0,
    this.maxSnoozeCount = 2,
    this.quranGoal,
    this.interruptionReason,
    this.enforcementStopFailed = false,
  });

  bool get isActive => status == FocusSessionStatus.active;
  bool get isSnoozed => status == FocusSessionStatus.snoozed;
  bool get isEnforcing => status.isEnforcing;
  bool get isCompleted => status == FocusSessionStatus.completed;
  bool get isCancelled => status == FocusSessionStatus.cancelled;
  bool get isInterrupted => status == FocusSessionStatus.interrupted;

  bool get isTerminal =>
      status == FocusSessionStatus.completed ||
      status == FocusSessionStatus.cancelled ||
      status == FocusSessionStatus.interrupted;

  bool get canSnooze =>
      snoozeCount < maxSnoozeCount && (isActive || isSnoozed);

  FocusSessionState copyWith({
    String? sessionId,
    FocusWardType? wardType,
    FocusSessionStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    int? snoozeCount,
    int? maxSnoozeCount,
    QuranReadingGoal? quranGoal,
    String? interruptionReason,
    bool? enforcementStopFailed,
  }) {
    return FocusSessionState(
      sessionId: sessionId ?? this.sessionId,
      wardType: wardType ?? this.wardType,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
      quranGoal: quranGoal ?? this.quranGoal,
      interruptionReason: interruptionReason ?? this.interruptionReason,
      enforcementStopFailed:
          enforcementStopFailed ?? this.enforcementStopFailed,
    );
  }

  factory FocusSessionState.initial() {
    return FocusSessionState(
      sessionId: '',
      wardType: FocusWardType.morningAzkar,
      status: FocusSessionStatus.idle,
      startTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusSessionState &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          wardType == other.wardType &&
          status == other.status &&
          snoozeCount == other.snoozeCount &&
          maxSnoozeCount == other.maxSnoozeCount &&
          quranGoal == other.quranGoal &&
          interruptionReason == other.interruptionReason &&
          enforcementStopFailed == other.enforcementStopFailed;

  @override
  int get hashCode =>
      sessionId.hashCode ^
      wardType.hashCode ^
      status.hashCode ^
      snoozeCount.hashCode ^
      maxSnoozeCount.hashCode ^
      (quranGoal?.hashCode ?? 0) ^
      (interruptionReason?.hashCode ?? 0) ^
      enforcementStopFailed.hashCode;
}
