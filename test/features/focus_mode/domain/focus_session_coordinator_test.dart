import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/ward_completion_event.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';

class FakeFocusEnforcementPort implements FocusEnforcementPort {
  bool isEnforcementRunning = false;
  String? activeSessionId;
  String? activeWardTitle;
  int startCalls = 0;
  int stopCalls = 0;
  bool shouldStopFail = false;

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async {
    startCalls++;
    isEnforcementRunning = true;
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
    isEnforcementRunning = false;
    activeSessionId = null;
    return true;
  }

  @override
  Future<bool> isEnforcing() async => isEnforcementRunning;

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async {
    return FocusEnforcementStatus(
      isRunning: isEnforcementRunning,
      sessionId: activeSessionId,
      wardTitle: activeWardTitle,
      state: isEnforcementRunning
          ? NativeEnforcementState.active
          : NativeEnforcementState.stopped,
    );
  }
}

void main() {
  late InMemoryAdhkarCompletionPort adhkarPort;
  late InMemoryQuranReadingCompletionPort quranPort;
  late FakeFocusEnforcementPort enforcementPort;
  late FocusSessionCoordinator coordinator;

  setUp(() {
    adhkarPort = InMemoryAdhkarCompletionPort();
    quranPort = InMemoryQuranReadingCompletionPort();
    enforcementPort = FakeFocusEnforcementPort();

    coordinator = FocusSessionCoordinator(
      adhkarPort: adhkarPort,
      quranPort: quranPort,
      enforcementPort: enforcementPort,
    );
  });

  tearDown(() {
    coordinator.dispose();
    adhkarPort.dispose();
    quranPort.dispose();
  });

  group('FocusSessionCoordinator - Lifecycle & Adhkar Integration', () {
    test('initial state is idle', () {
      expect(coordinator.state.status, equals(FocusSessionStatus.idle));
    });

    test('startSession activates the session and triggers enforcement port', () async {
      await coordinator.startSession(
        sessionId: 'session_morning_1',
        wardType: FocusWardType.morningAzkar,
      );

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(coordinator.state.wardType, equals(FocusWardType.morningAzkar));
      expect(enforcementPort.startCalls, equals(1));
      expect(enforcementPort.isEnforcementRunning, isTrue);
    });

    test('partial adhkar event keeps session active and does not stop enforcement', () async {
      await coordinator.startSession(
        sessionId: 'session_morning_1',
        wardType: FocusWardType.morningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.progress(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          completedCount: 5,
          totalCount: 15,
        ),
      );

      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(enforcementPort.stopCalls, equals(0));
    });

    test('full adhkar completion transitions session to completed and stops enforcement', () async {
      await coordinator.startSession(
        sessionId: 'session_morning_1',
        wardType: FocusWardType.morningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 15,
        ),
      );

      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(coordinator.state.endTime, isNotNull);
      expect(enforcementPort.stopCalls, equals(1));
      expect(coordinator.state.enforcementStopFailed, isFalse);
    });
  });

  group('FocusSessionCoordinator - Quran Reading Integration', () {
    test('genuine page dwell completes Quran goal when target is reached', () async {
      await coordinator.startSession(
        sessionId: 'session_quran_1',
        wardType: FocusWardType.quranReading,
        quranGoal: QuranReadingGoal.pageCount(2, minDurationPerPage: const Duration(seconds: 20)),
      );

      // Genuine reading on page 1 (25 seconds)
      quranPort.recordPageDwell(pageNumber: 1, timeSpent: const Duration(seconds: 25));
      await pumpEventQueue();
      expect(coordinator.state.status, equals(FocusSessionStatus.active));

      // Genuine reading on page 2 (30 seconds)
      quranPort.recordPageDwell(pageNumber: 2, timeSpent: const Duration(seconds: 30));
      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(enforcementPort.stopCalls, equals(1));
    });
  });

  group('FocusSessionCoordinator - Snooze, Cancellation & Interruption', () {
    test('snooze works up to max 2 times, 3rd snooze is rejected', () async {
      await coordinator.startSession(
        sessionId: 'session_test',
        wardType: FocusWardType.morningAzkar,
      );

      // 1st snooze
      expect(await coordinator.snoozeSession(), isTrue);
      expect(coordinator.state.status, equals(FocusSessionStatus.snoozed));
      expect(coordinator.state.snoozeCount, equals(1));

      // Resume
      await coordinator.resumeFromSnooze();
      expect(coordinator.state.status, equals(FocusSessionStatus.active));

      // 2nd snooze
      expect(await coordinator.snoozeSession(), isTrue);
      expect(coordinator.state.snoozeCount, equals(2));

      // Resume
      await coordinator.resumeFromSnooze();

      // 3rd snooze: must be rejected
      expect(await coordinator.snoozeSession(), isFalse);
      expect(coordinator.state.snoozeCount, equals(2));
    });

    test('cancelSession sets status to cancelled and calls enforcement stop', () async {
      await coordinator.startSession(
        sessionId: 'session_cancel_test',
        wardType: FocusWardType.eveningAzkar,
      );

      await coordinator.cancelSession();

      expect(coordinator.state.status, equals(FocusSessionStatus.cancelled));
      expect(coordinator.state.isTerminal, isTrue);
      expect(enforcementPort.stopCalls, equals(1));
    });

    test('interruptSession sets status to interrupted and records reason', () async {
      await coordinator.startSession(
        sessionId: 'session_interrupt_test',
        wardType: FocusWardType.postPrayerAzkar,
      );

      await coordinator.interruptSession('PERMISSIONS_REVOKED');

      expect(coordinator.state.status, equals(FocusSessionStatus.interrupted));
      expect(coordinator.state.interruptionReason, equals('PERMISSIONS_REVOKED'));
      expect(enforcementPort.stopCalls, equals(1));
    });
  });
}
