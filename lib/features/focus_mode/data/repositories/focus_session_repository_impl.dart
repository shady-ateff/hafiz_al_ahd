import '../../domain/entities/focus_enforcement_operation.dart';
import '../../domain/entities/focus_session_progress.dart';
import '../../domain/entities/focus_session_state.dart';
import '../../domain/repositories/focus_session_repository.dart';
import '../datasources/focus_session_local_data_source.dart';
import '../models/focus_enforcement_operation_model.dart';
import '../models/focus_session_model.dart';
import '../models/focus_session_progress_model.dart';

class FocusSessionRepositoryImpl implements FocusSessionRepository {
  final FocusSessionLocalDataSource localDataSource;

  FocusSessionRepositoryImpl({required this.localDataSource});

  @override
  Future<void> saveActiveSession(
    FocusSessionState session, {
    FocusSessionProgress? progress,
    FocusEnforcementOperation? pendingOperation,
  }) async {
    await localDataSource.saveActiveSession(
      FocusSessionModel.fromEntity(session),
      progress: progress != null
          ? FocusSessionProgressModel.fromEntity(progress)
          : null,
      pendingOperation: pendingOperation != null
          ? FocusEnforcementOperationModel.fromEntity(pendingOperation)
          : null,
    );
  }

  @override
  Future<FocusSessionState?> getActiveSession() async {
    return await localDataSource.getActiveSession();
  }

  @override
  Future<void> clearActiveSession() async {
    await localDataSource.clearActiveSession();
  }

  @override
  Future<void> saveProgress(FocusSessionProgress progress) async {
    await localDataSource.saveProgress(
      FocusSessionProgressModel.fromEntity(progress),
    );
  }

  @override
  Future<FocusSessionProgress?> getProgress(String sessionId) async {
    return await localDataSource.getProgress(sessionId);
  }

  @override
  Future<void> archiveSession(
    FocusSessionState session, {
    FocusEnforcementOperation? pendingOperation,
  }) async {
    await localDataSource.archiveSession(
      FocusSessionModel.fromEntity(session),
      pendingOperation: pendingOperation != null
          ? FocusEnforcementOperationModel.fromEntity(pendingOperation)
          : null,
    );
  }

  @override
  Future<List<FocusSessionState>> getSessionHistory({int limit = 20}) async {
    return await localDataSource.getSessionHistory(limit: limit);
  }

  @override
  Future<void> saveEnforcementOperation(
      FocusEnforcementOperation operation) async {
    await localDataSource.saveEnforcementOperation(
      FocusEnforcementOperationModel.fromEntity(operation),
    );
  }

  @override
  Future<List<FocusEnforcementOperation>>
      getPendingEnforcementOperations() async {
    return await localDataSource.getPendingEnforcementOperations();
  }

  @override
  Future<void> updateEnforcementOperationStatus({
    required String operationId,
    required EnforcementOperationStatus status,
    String? error,
  }) async {
    await localDataSource.updateEnforcementOperationStatus(
      operationId: operationId,
      status: status.name,
      error: error,
    );
  }

  @override
  Future<void> deleteEnforcementOperation(String operationId) async {
    await localDataSource.deleteEnforcementOperation(operationId);
  }
}
