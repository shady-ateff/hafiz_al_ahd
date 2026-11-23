import '../entities/focus_enforcement_operation.dart';
import '../entities/focus_session_progress.dart';
import '../entities/focus_session_state.dart';

/// Repository contract for transactional persistence of Focus Mode sessions,
/// incremental progress, and pending enforcement operations.
abstract class FocusSessionRepository {
  /// Atomically saves or updates the currently active/snoozed session.
  /// Optionally persists initial progress and an initial pending operation in the same transaction.
  Future<void> saveActiveSession(
    FocusSessionState session, {
    FocusSessionProgress? progress,
    FocusEnforcementOperation? pendingOperation,
  });

  /// Retrieves the currently active/snoozed session from local storage, if any.
  Future<FocusSessionState?> getActiveSession();

  /// Clears the active session marker (marking it inactive or archived).
  Future<void> clearActiveSession();

  /// Saves or updates incremental progress made in an active session.
  Future<void> saveProgress(FocusSessionProgress progress);

  /// Retrieves incremental progress for the specified [sessionId].
  Future<FocusSessionProgress?> getProgress(String sessionId);

  /// Atomically archives a terminal session (completed, cancelled, interrupted)
  /// and updates any associated pending operation in a single atomic transaction.
  Future<void> archiveSession(
    FocusSessionState session, {
    FocusEnforcementOperation? pendingOperation,
  });

  /// Retrieves historical archived sessions in reverse chronological order.
  Future<List<FocusSessionState>> getSessionHistory({int limit = 20});

  /// Persists a new or updated enforcement operation.
  Future<void> saveEnforcementOperation(FocusEnforcementOperation operation);

  /// Retrieves all operations that are pending or failed and need execution/retry.
  Future<List<FocusEnforcementOperation>> getPendingEnforcementOperations();

  /// Updates the status and optional error message of an enforcement operation.
  Future<void> updateEnforcementOperationStatus({
    required String operationId,
    required EnforcementOperationStatus status,
    String? error,
  });

  /// Removes a completed enforcement operation from storage.
  Future<void> deleteEnforcementOperation(String operationId);
}
