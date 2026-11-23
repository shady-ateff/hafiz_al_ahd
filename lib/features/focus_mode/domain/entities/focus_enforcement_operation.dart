/// The type of enforcement operation requested by the domain.
enum EnforcementOperationType {
  start,
  stop,
  snooze,
}

/// The lifecycle status of a persisted enforcement operation.
enum EnforcementOperationStatus {
  pending,
  executing,
  completed,
  failed,
}

/// Represents a distinct operation dispatched to the native engine that must be
/// tracked and retried if the system crashes or the native engine encounters an error.
class FocusEnforcementOperation {
  final String operationId;
  final String sessionId;
  final EnforcementOperationType operationType;
  final EnforcementOperationStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;

  const FocusEnforcementOperation({
    required this.operationId,
    required this.sessionId,
    required this.operationType,
    required this.status,
    this.retryCount = 0,
    required this.createdAt,
    this.lastAttemptAt,
    this.lastError,
  });

  bool get isPending => status == EnforcementOperationStatus.pending;
  bool get isFailed => status == EnforcementOperationStatus.failed;
  bool get isCompleted => status == EnforcementOperationStatus.completed;

  FocusEnforcementOperation copyWith({
    String? operationId,
    String? sessionId,
    EnforcementOperationType? operationType,
    EnforcementOperationStatus? status,
    int? retryCount,
    DateTime? createdAt,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return FocusEnforcementOperation(
      operationId: operationId ?? this.operationId,
      sessionId: sessionId ?? this.sessionId,
      operationType: operationType ?? this.operationType,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusEnforcementOperation &&
          runtimeType == other.runtimeType &&
          operationId == other.operationId &&
          sessionId == other.sessionId &&
          operationType == other.operationType &&
          status == other.status &&
          retryCount == other.retryCount &&
          lastError == other.lastError;

  @override
  int get hashCode =>
      operationId.hashCode ^
      sessionId.hashCode ^
      operationType.hashCode ^
      status.hashCode ^
      retryCount.hashCode ^
      (lastError?.hashCode ?? 0);
}
