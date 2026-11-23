import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_operation.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_state.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/ward_completion_event.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';

class StubEnforcementPort implements FocusEnforcementPort {
  bool isRunning = false;
  String? activeSessionId;
  String? activeWardTitle;
  bool shouldStopFail = false;

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
    return true;
  }

  @override
  Future<bool> stopEnforcement() async {
    stopCalls++;
    if (shouldStopFail) {
      return false;
    }
    isRunning = false;
    activeSessionId = null;
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
      state: isRunning ? NativeEnforcementState.active : NativeEnforcementState.stopped,
    );
  }
}

void main() {
  late InMemoryAdhkarCompletionPort adhkarPort;
  late InMemoryQuranReadingCompletionPort quranPort;
  late StubEnforcementPort enforcementPort;
  late FocusSessionLocalDataSource localDataSource;
  late FocusSessionRepositoryImpl repository;
  late FocusSessionCoordinator coordinator;

  setUp(() {
    adhkarPort = InMemoryAdhkarCompletionPort();
    quranPort = InMemoryQuranReadingCompletionPort();
    enforcementPort = StubEnforcementPort();
    localDataSource = FocusSessionLocalDataSourceImpl.inMemory();
    repository = FocusSessionRepositoryImpl(localDataSource: localDataSource);

    coordinator = FocusSessionCoordinator(
      adhkarPort: adhkarPort,
      quranPort: quranPort,
      enforcementPort: enforcementPort,
      repository: repository,
    );
  });

  tearDown(() {
    coordinator.dispose();
    adhkarPort.dispose();
    quranPort.dispose();
  });

  group('FocusSessionCoordinator — Integration with SQLite Repository', () {
    test('startSession persists session, progress, and dispatches native start', () async {
      await coordinator.startSession(
        sessionId: 'session_persisted_1',
        wardType: FocusWardType.morningAzkar,
      );

      final active = await repository.getActiveSession();
      final progress = await repository.getProgress('session_persisted_1');
      final pendingOps = await repository.getPendingEnforcementOperations();

      expect(active, isNotNull);
      expect(active!.sessionId, equals('session_persisted_1'));
      expect(active.status, equals(FocusSessionStatus.active));
      expect(progress, isNotNull);
      // Start operation was executed successfully, so pending op is removed
      expect(pendingOps, isEmpty);
      expect(enforcementPort.startCalls, equals(1));
      expect(enforcementPort.activeSessionId, equals('session_persisted_1'));
    });

    test('progress updates are persisted incrementally to storage', () async {
      await coordinator.startSession(
        sessionId: 'session_persisted_adhkar',
        wardType: FocusWardType.morningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.progress(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          completedCount: 3,
          totalCount: 10,
          completedKeys: {'z1', 'z2', 'z3'},
          requiredKeys: {'z1', 'z2', 'z3', 'z4', 'z5', 'z6', 'z7', 'z8', 'z9', 'z10'},
          sessionId: 'session_persisted_adhkar',
        ),
      );

      await pumpEventQueue();

      final progress = await repository.getProgress('session_persisted_adhkar');
      expect(progress, isNotNull);
      expect(progress!.completedItemKeys.length, equals(3));
      expect(progress.completedItemKeys, containsAll({'z1', 'z2', 'z3'}));
    });

    test('snoozeSession persists updated snooze count', () async {
      await coordinator.startSession(
        sessionId: 'session_snooze_persist',
        wardType: FocusWardType.morningAzkar,
      );

      final snoozed = await coordinator.snoozeSession();
      expect(snoozed, isTrue);

      final active = await repository.getActiveSession();
      expect(active, isNotNull);
      expect(active!.status, equals(FocusSessionStatus.snoozed));
      expect(active.snoozeCount, equals(1));
    });

    test('full completion archives session atomically and cleans up stop operation on success', () async {
      await coordinator.startSession(
        sessionId: 'session_complete_persist',
        wardType: FocusWardType.morningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 5,
          sessionId: 'session_complete_persist',
        ),
      );

      await pumpEventQueue();

      final active = await repository.getActiveSession();
      expect(active, isNull); // Cleared from active

      final history = await repository.getSessionHistory();
      expect(history.length, equals(1));
      expect(history.first.sessionId, equals('session_complete_persist'));
      expect(history.first.status, equals(FocusSessionStatus.completed));

      final pendingOps = await repository.getPendingEnforcementOperations();
      expect(pendingOps, isEmpty); // Deleted on success
      expect(enforcementPort.stopCalls, equals(1));
    });

    test('native stop failure leaves pending stop operation in DB for RecoveryManager', () async {
      enforcementPort.shouldStopFail = true; // Native stop fails!

      await coordinator.startSession(
        sessionId: 'session_fail_stop_persist',
        wardType: FocusWardType.eveningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.eveningAzkar,
          categoryKey: 'evening',
          totalCount: 5,
          sessionId: 'session_fail_stop_persist',
        ),
      );

      await pumpEventQueue();

      // State is completed (worship finished)
      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(coordinator.state.enforcementStopFailed, isTrue);

      // Pending stop operation is stored in DB with status failed
      final pendingOps = await repository.getPendingEnforcementOperations();
      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.operationType, equals(EnforcementOperationType.stop));
      expect(pendingOps.first.status, equals(EnforcementOperationStatus.failed));
    });

    test('restoreSession correctly hydrates coordinator state and subscriptions from repository', () async {
      final session = FocusSessionState(
        sessionId: 'session_hydrated',
        wardType: FocusWardType.quranReading,
        status: FocusSessionStatus.active,
        startTime: DateTime.now().subtract(const Duration(minutes: 10)),
        quranGoal: QuranReadingGoal.pageCount(3, minDurationPerPage: const Duration(seconds: 20)),
      );

      coordinator.restoreSession(session: session);

      expect(coordinator.state.sessionId, equals('session_hydrated'));
      expect(coordinator.state.wardType, equals(FocusWardType.quranReading));
      expect(coordinator.state.isActive, isTrue);

      // Verify that after hydration, ports are active and will complete the goal
      quranPort.recordPageDwell(pageNumber: 1, timeSpent: const Duration(seconds: 25));
      quranPort.recordPageDwell(pageNumber: 2, timeSpent: const Duration(seconds: 25));
      quranPort.recordPageDwell(pageNumber: 3, timeSpent: const Duration(seconds: 25));

      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(enforcementPort.stopCalls, equals(1));
    });
  });
}
