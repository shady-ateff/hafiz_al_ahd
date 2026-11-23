import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_operation.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_progress.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_state.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_recovery_manager.dart';

class TestRecoveryEnforcementPort implements FocusEnforcementPort {
  bool isRunning = false;
  String? activeSessionId;
  String? activeWardTitle;
  NativeEnforcementState state = NativeEnforcementState.stopped;

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async {
    startCalls++;
    isRunning = true;
    activeSessionId = sessionId;
    activeWardTitle = wardTitle;
    state = NativeEnforcementState.active;
    return true;
  }

  @override
  Future<bool> stopEnforcement() async {
    stopCalls++;
    isRunning = false;
    activeSessionId = null;
    activeWardTitle = null;
    state = NativeEnforcementState.stopped;
    return true;
  }

  @override
  Future<bool> isEnforcing() async => isRunning;

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async {
    return FocusEnforcementStatus(
      isRunning: isRunning,
      sessionId: activeSessionId,
      wardTitle: activeWardTitle,
      state: state,
    );
  }
}

void main() {
  late FocusSessionLocalDataSource localDataSource;
  late FocusSessionRepositoryImpl repository;
  late TestRecoveryEnforcementPort enforcementPort;
  late FocusSessionRecoveryManager recoveryManager;

  setUp(() {
    localDataSource = FocusSessionLocalDataSourceImpl.inMemory();
    repository = FocusSessionRepositoryImpl(localDataSource: localDataSource);
    enforcementPort = TestRecoveryEnforcementPort();
    recoveryManager = FocusSessionRecoveryManager(
      repository: repository,
      enforcementPort: enforcementPort,
    );
  });

  group('FocusSessionRecoveryManager — Deep Reconciliation Matrix', () {
    test('Healthy Match: Resumes active session and progress when sessionIds match', () async {
      final session = FocusSessionState(
        sessionId: 'session_match_100',
        wardType: FocusWardType.morningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );
      final progress = FocusSessionProgress(
        sessionId: 'session_match_100',
        completedItemKeys: {'z1', 'z2'},
        updatedAt: DateTime.now(),
      );

      await repository.saveActiveSession(session, progress: progress);

      // Setup native engine to match exactly
      enforcementPort.isRunning = true;
      enforcementPort.activeSessionId = 'session_match_100';
      enforcementPort.state = NativeEnforcementState.active;

      final result = await recoveryManager.reconcileAndRecover();

      expect(result.action, equals(FocusRecoveryAction.resumed));
      expect(result.session, isNotNull);
      expect(result.session!.sessionId, equals('session_match_100'));
      expect(result.progress, isNotNull);
      expect(result.progress!.completedItemKeys, contains('z1'));
      expect(enforcementPort.startCalls, equals(0)); // Didn't need to re-start
    });

    test('Conflict Resolution: Dismantles mismatched native session and restarts active session', () async {
      final session = FocusSessionState(
        sessionId: 'session_active_current',
        wardType: FocusWardType.morningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );
      await repository.saveActiveSession(session);

      // Native service is running an old or foreign session
      enforcementPort.isRunning = true;
      enforcementPort.activeSessionId = 'session_old_stale';
      enforcementPort.state = NativeEnforcementState.active;

      final result = await recoveryManager.reconcileAndRecover();

      expect(result.action, equals(FocusRecoveryAction.conflictResolved));
      expect(enforcementPort.stopCalls, equals(1)); // Stopped old session
      expect(enforcementPort.startCalls, equals(1)); // Re-started current session
      expect(enforcementPort.activeSessionId, equals('session_active_current'));
    });

    test('Orphaned Native Enforcement: Safely stops native service when DB has no active session', () async {
      // DB is clean (no active session)
      // But Native service is running
      enforcementPort.isRunning = true;
      enforcementPort.activeSessionId = 'session_ghost';
      enforcementPort.state = NativeEnforcementState.active;

      final result = await recoveryManager.reconcileAndRecover();

      expect(result.action, equals(FocusRecoveryAction.orphanedStopped));
      expect(enforcementPort.stopCalls, equals(1));
      expect(enforcementPort.isRunning, isFalse);
    });

    test('Killed Service Recovery: Restores native enforcement when active session was stopped', () async {
      final session = FocusSessionState(
        sessionId: 'session_survivor',
        wardType: FocusWardType.eveningAzkar,
        status: FocusSessionStatus.active,
        startTime: DateTime.now(),
      );
      await repository.saveActiveSession(session);

      // Native service is completely stopped (e.g. killed by Android OS)
      enforcementPort.isRunning = false;
      enforcementPort.activeSessionId = null;

      final result = await recoveryManager.reconcileAndRecover();

      expect(result.action, equals(FocusRecoveryAction.enforcementRestored));
      expect(enforcementPort.startCalls, equals(1));
      expect(enforcementPort.activeSessionId, equals('session_survivor'));
    });

    test('Pending Operations: Executes and clears pending stop operations upon recovery', () async {
      final stopOp = FocusEnforcementOperation(
        operationId: 'op_stop_pending',
        sessionId: 'session_past',
        operationType: EnforcementOperationType.stop,
        status: EnforcementOperationStatus.pending,
        createdAt: DateTime.now(),
      );
      await repository.saveEnforcementOperation(stopOp);

      enforcementPort.isRunning = true; // Still running from unstopped session

      final processed = await recoveryManager.processPendingOperations();

      expect(processed, equals(1));
      expect(enforcementPort.stopCalls, equals(1));

      final remaining = await repository.getPendingEnforcementOperations();
      expect(remaining, isEmpty);
    });

    test('Clean Idle: Returns idle when neither DB nor Native has active sessions', () async {
      final result = await recoveryManager.reconcileAndRecover();

      expect(result.action, equals(FocusRecoveryAction.idle));
      expect(enforcementPort.startCalls, equals(0));
      expect(enforcementPort.stopCalls, equals(0));
    });
  });
}
