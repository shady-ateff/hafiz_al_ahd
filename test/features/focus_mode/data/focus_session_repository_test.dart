import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_operation.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_progress.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_state.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';

void main() {
  late FocusSessionLocalDataSource localDataSource;
  late FocusSessionRepositoryImpl repository;

  setUp(() {
    localDataSource = FocusSessionLocalDataSourceImpl.inMemory();
    repository = FocusSessionRepositoryImpl(localDataSource: localDataSource);
  });

  group('FocusSessionRepository — Atomic Persistence & Operations', () {
    test('saveActiveSession persists session and progress atomically', () async {
      final session = FocusSessionState(
        sessionId: 'session_101',
        wardType: FocusWardType.morningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );

      final progress = FocusSessionProgress(
        sessionId: 'session_101',
        requiredItemKeys: {'zikr_1', 'zikr_2'},
        completedItemKeys: {'zikr_1'},
        updatedAt: DateTime.now(),
      );

      final startOp = FocusEnforcementOperation(
        operationId: 'op_start_101',
        sessionId: 'session_101',
        operationType: EnforcementOperationType.start,
        status: EnforcementOperationStatus.pending,
        createdAt: DateTime.now(),
      );

      await repository.saveActiveSession(
        session,
        progress: progress,
        pendingOperation: startOp,
      );

      final active = await repository.getActiveSession();
      final savedProgress = await repository.getProgress('session_101');
      final pendingOps = await repository.getPendingEnforcementOperations();

      expect(active, isNotNull);
      expect(active!.sessionId, equals('session_101'));
      expect(active.status, equals(FocusSessionStatus.active));

      expect(savedProgress, isNotNull);
      expect(savedProgress!.completedItemKeys, contains('zikr_1'));
      expect(savedProgress.requiredItemKeys, contains('zikr_2'));

      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.operationId, equals('op_start_101'));
    });

    test('saving a new active session enforces strictly one active session', () async {
      final session1 = FocusSessionState(
        sessionId: 'session_1',
        wardType: FocusWardType.morningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );

      final session2 = FocusSessionState(
        sessionId: 'session_2',
        wardType: FocusWardType.eveningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );

      await repository.saveActiveSession(session1);
      await repository.saveActiveSession(session2);

      final active = await repository.getActiveSession();
      expect(active, isNotNull);
      expect(active!.sessionId, equals('session_2'));
    });

    test('archiveSession marks session as inactive and stores in history with pending operation', () async {
      final session = FocusSessionState(
        sessionId: 'session_done_1',
        wardType: FocusWardType.quranReading,
        status: FocusSessionStatus.completed,
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
        endTime: DateTime.now(),
        quranGoal: QuranReadingGoal.pageCount(2),
      );

      final stopOp = FocusEnforcementOperation(
        operationId: 'op_stop_done_1',
        sessionId: 'session_done_1',
        operationType: EnforcementOperationType.stop,
        status: EnforcementOperationStatus.pending,
        createdAt: DateTime.now(),
      );

      await repository.archiveSession(session, pendingOperation: stopOp);

      final active = await repository.getActiveSession();
      expect(active, isNull);

      final history = await repository.getSessionHistory();
      expect(history.length, equals(1));
      expect(history.first.sessionId, equals('session_done_1'));
      expect(history.first.status, equals(FocusSessionStatus.completed));

      final pendingOps = await repository.getPendingEnforcementOperations();
      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.operationType, equals(EnforcementOperationType.stop));
    });

    test('updateEnforcementOperationStatus increments retry count and records error', () async {
      final op = FocusEnforcementOperation(
        operationId: 'op_retry_test',
        sessionId: 'session_retry',
        operationType: EnforcementOperationType.stop,
        status: EnforcementOperationStatus.pending,
        createdAt: DateTime.now(),
      );

      await repository.saveEnforcementOperation(op);

      await repository.updateEnforcementOperationStatus(
        operationId: 'op_retry_test',
        status: EnforcementOperationStatus.failed,
        error: 'Connection timeout with native daemon',
      );

      final pendingOps = await repository.getPendingEnforcementOperations();
      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.status, equals(EnforcementOperationStatus.failed));
      expect(pendingOps.first.retryCount, equals(1));
      expect(pendingOps.first.lastError, equals('Connection timeout with native daemon'));

      await repository.deleteEnforcementOperation('op_retry_test');
      final remainingOps = await repository.getPendingEnforcementOperations();
      expect(remainingOps, isEmpty);
    });
  });
}
