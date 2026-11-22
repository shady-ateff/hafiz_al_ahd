import '../../domain/entities/focus_enforcement_operation.dart';

class FocusEnforcementOperationModel extends FocusEnforcementOperation {
  const FocusEnforcementOperationModel({
    required super.operationId,
    required super.sessionId,
    required super.operationType,
    required super.status,
    super.retryCount,
    required super.createdAt,
    super.lastAttemptAt,
    super.lastError,
  });

  factory FocusEnforcementOperationModel.fromEntity(
      FocusEnforcementOperation entity) {
    return FocusEnforcementOperationModel(
      operationId: entity.operationId,
      sessionId: entity.sessionId,
      operationType: entity.operationType,
      status: entity.status,
      retryCount: entity.retryCount,
      createdAt: entity.createdAt,
      lastAttemptAt: entity.lastAttemptAt,
      lastError: entity.lastError,
    );
  }

  factory FocusEnforcementOperationModel.fromDbMap(Map<String, dynamic> map) {
    EnforcementOperationType opType = EnforcementOperationType.stop;
    final opStr = map['operation_type'] as String?;
    if (opStr != null) {
      for (final t in EnforcementOperationType.values) {
        if (t.name == opStr) {
          opType = t;
          break;
        }
      }
    }

    EnforcementOperationStatus opStatus = EnforcementOperationStatus.pending;
    final statusStr = map['status'] as String?;
    if (statusStr != null) {
      for (final s in EnforcementOperationStatus.values) {
        if (s.name == statusStr) {
          opStatus = s;
          break;
        }
      }
    }

    final createdAtEpoch = map['created_at'] as int? ?? 0;
    final lastAttemptEpoch = map['last_attempt_at'] as int?;

    return FocusEnforcementOperationModel(
      operationId: map['operation_id'] as String? ?? '',
      sessionId: map['session_id'] as String? ?? '',
      operationType: opType,
      status: opStatus,
      retryCount: map['retry_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtEpoch),
      lastAttemptAt: lastAttemptEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(lastAttemptEpoch)
          : null,
      lastError: map['last_error'] as String?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'operation_id': operationId,
      'session_id': sessionId,
      'operation_type': operationType.name,
      'status': status.name,
      'retry_count': retryCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
      'last_error': lastError,
    };
  }
}
