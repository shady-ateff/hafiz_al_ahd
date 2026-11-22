/// Detailed execution states of the native enforcement service.
enum NativeEnforcementState {
  stopped,
  starting,
  active,
  snoozed,
  stopping,
  error,
}

/// Comprehensive status reported by the native enforcement engine.
/// Carries [sessionId] to allow dual-identity verification and prevent
/// treating an orphaned or stale service as active for the current session.
class FocusEnforcementStatus {
  final bool isRunning;
  final String? sessionId;
  final String? wardTitle;
  final NativeEnforcementState state;
  final int snoozeRemaining;
  final DateTime? startedAt;
  final String? lastError;

  const FocusEnforcementStatus({
    required this.isRunning,
    this.sessionId,
    this.wardTitle,
    this.state = NativeEnforcementState.stopped,
    this.snoozeRemaining = 2,
    this.startedAt,
    this.lastError,
  });

  bool get isActive => isRunning && state == NativeEnforcementState.active;
  bool get isSnoozed => isRunning && state == NativeEnforcementState.snoozed;

  factory FocusEnforcementStatus.stopped() {
    return const FocusEnforcementStatus(
      isRunning: false,
      state: NativeEnforcementState.stopped,
    );
  }

  factory FocusEnforcementStatus.fromMap(Map<dynamic, dynamic> map) {
    final stateStr = map['state'] as String?;
    NativeEnforcementState state = NativeEnforcementState.stopped;
    if (stateStr != null) {
      for (final s in NativeEnforcementState.values) {
        if (s.name.toLowerCase() == stateStr.toLowerCase()) {
          state = s;
          break;
        }
      }
    }

    final startedAtEpoch = map['startedAt'] as int?;

    return FocusEnforcementStatus(
      isRunning: map['isRunning'] as bool? ?? false,
      sessionId: map['sessionId'] as String?,
      wardTitle: map['wardTitle'] as String?,
      state: state,
      snoozeRemaining: map['snoozeRemaining'] as int? ?? 2,
      startedAt: startedAtEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(startedAtEpoch)
          : null,
      lastError: map['lastError'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isRunning': isRunning,
      'sessionId': sessionId,
      'wardTitle': wardTitle,
      'state': state.name,
      'snoozeRemaining': snoozeRemaining,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'lastError': lastError,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusEnforcementStatus &&
          runtimeType == other.runtimeType &&
          isRunning == other.isRunning &&
          sessionId == other.sessionId &&
          wardTitle == other.wardTitle &&
          state == other.state &&
          snoozeRemaining == other.snoozeRemaining &&
          lastError == other.lastError;

  @override
  int get hashCode =>
      isRunning.hashCode ^
      (sessionId?.hashCode ?? 0) ^
      (wardTitle?.hashCode ?? 0) ^
      state.hashCode ^
      snoozeRemaining.hashCode ^
      (lastError?.hashCode ?? 0);
}
