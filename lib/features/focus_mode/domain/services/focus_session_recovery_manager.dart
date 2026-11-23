import '../entities/focus_enforcement_operation.dart';
import '../entities/focus_session_progress.dart';
import '../entities/focus_session_state.dart';
import '../entities/focus_ward_type.dart';
import '../ports/focus_enforcement_port.dart';
import '../repositories/focus_session_repository.dart';

enum FocusRecoveryAction {
  idle,
  resumed,
  enforcementRestored,
  conflictResolved,
  orphanedStopped,
  pendingOperationsProcessed,
}

class FocusRecoveryResult {
  final FocusRecoveryAction action;
  final FocusSessionState? session;
  final FocusSessionProgress? progress;
  final String? message;

  const FocusRecoveryResult({
    required this.action,
    this.session,
    this.progress,
    this.message,
  });

  factory FocusRecoveryResult.idle() =>
      const FocusRecoveryResult(action: FocusRecoveryAction.idle);

  factory FocusRecoveryResult.resumed({
    required FocusSessionState session,
    FocusSessionProgress? progress,
  }) =>
      FocusRecoveryResult(
        action: FocusRecoveryAction.resumed,
        session: session,
        progress: progress,
        message: 'Active session successfully restored with matching native state.',
      );

  factory FocusRecoveryResult.enforcementRestored({
    required FocusSessionState session,
    FocusSessionProgress? progress,
  }) =>
      FocusRecoveryResult(
        action: FocusRecoveryAction.enforcementRestored,
        session: session,
        progress: progress,
        message: 'Active session preserved; native enforcement re-established.',
      );

  factory FocusRecoveryResult.conflictResolved({
    required FocusSessionState session,
  }) =>
      FocusRecoveryResult(
        action: FocusRecoveryAction.conflictResolved,
        session: session,
        message: 'Mismatched native session stopped and active session enforcement re-aligned.',
      );

  factory FocusRecoveryResult.orphanedStopped() =>
      const FocusRecoveryResult(
        action: FocusRecoveryAction.orphanedStopped,
        message: 'Orphaned native enforcement safely dismantled.',
      );
}

/// Service in Domain that arbitrates state consistency between SQLite persistence
/// and the Native Android enforcement service upon cold start or process resumption.
class FocusSessionRecoveryManager {
  final FocusSessionRepository repository;
  final FocusEnforcementPort enforcementPort;

  const FocusSessionRecoveryManager({
    required this.repository,
    required this.enforcementPort,
  });

  /// Executes full state reconciliation and pending operations processing.
  Future<FocusRecoveryResult> reconcileAndRecover() async {
    // 1. Process any pending/failed operations first (Crash Consistency)
    await processPendingOperations();

    // 2. Fetch persisted active session and live native enforcement status
    final activeSession = await repository.getActiveSession();
    final nativeStatus = await enforcementPort.getEnforcementStatus();

    // 3. Matrix Reconciliation
    if (activeSession != null && (activeSession.isActive || activeSession.isSnoozed)) {
      final progress = await repository.getProgress(activeSession.sessionId);

      if (nativeStatus.isRunning) {
        if (nativeStatus.sessionId == activeSession.sessionId) {
          // Healthy Match: IDs match and service is active
          return FocusRecoveryResult.resumed(
            session: activeSession,
            progress: progress,
          );
        } else {
          // Session ID Mismatch: Native service belongs to an old/different session
          await enforcementPort.stopEnforcement();
          await enforcementPort.startEnforcement(
            sessionId: activeSession.sessionId,
            wardTitle: activeSession.wardType.displayName,
          );
          return FocusRecoveryResult.conflictResolved(session: activeSession);
        }
      } else {
        // Active in DB but Native Service is Stopped (Process death / killed service)
        // We preserve worship continuity: restart native enforcement for active session
        await enforcementPort.startEnforcement(
          sessionId: activeSession.sessionId,
          wardTitle: activeSession.wardType.displayName,
        );
        return FocusRecoveryResult.enforcementRestored(
          session: activeSession,
          progress: progress,
        );
      }
    } else {
      // No active session in DB
      if (nativeStatus.isRunning) {
        // Orphaned enforcement shield running without active session!
        // Stop it immediately so user is never locked out.
        await enforcementPort.stopEnforcement();
        return FocusRecoveryResult.orphanedStopped();
      } else {
        return FocusRecoveryResult.idle();
      }
    }
  }

  /// Processes and retries all pending operations.
  Future<int> processPendingOperations() async {
    final pendingOps = await repository.getPendingEnforcementOperations();
    int processedCount = 0;

    for (final op in pendingOps) {
      bool success = false;
      String? error;

      try {
        switch (op.operationType) {
          case EnforcementOperationType.stop:
            success = await enforcementPort.stopEnforcement();
            break;
          case EnforcementOperationType.start:
            success = await enforcementPort.startEnforcement(
              sessionId: op.sessionId,
              wardTitle: 'استئناف الورد',
            );
            break;
          case EnforcementOperationType.snooze:
            success = true;
            break;
        }
      } catch (e) {
        success = false;
        error = e.toString();
      }

      if (success) {
        await repository.deleteEnforcementOperation(op.operationId);
        processedCount++;
      } else {
        await repository.updateEnforcementOperationStatus(
          operationId: op.operationId,
          status: EnforcementOperationStatus.failed,
          error: error ?? 'Enforcement operation returned false',
        );
      }
    }

    return processedCount;
  }
}
