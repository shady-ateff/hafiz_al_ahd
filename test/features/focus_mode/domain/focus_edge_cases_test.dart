import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/ward_completion_event.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_completion_evaluator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';

class MockEnforcementPort implements FocusEnforcementPort {
  int startCalls = 0;
  int stopCalls = 0;
  bool shouldStopFail = false;
  String? currentSessionId;
  bool isRunning = true;

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async {
    startCalls++;
    isRunning = true;
    currentSessionId = sessionId;
    return true;
  }

  @override
  Future<bool> stopEnforcement() async {
    stopCalls++;
    if (shouldStopFail) {
      return false;
    }
    isRunning = false;
    currentSessionId = null;
    return true;
  }

  @override
  Future<bool> isEnforcing() async => isRunning;

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async {
    return FocusEnforcementStatus(
      isRunning: isRunning,
      sessionId: currentSessionId,
      state: isRunning
          ? NativeEnforcementState.active
          : NativeEnforcementState.stopped,
    );
  }
}

void main() {
  late InMemoryAdhkarCompletionPort adhkarPort;
  late InMemoryQuranReadingCompletionPort quranPort;
  late MockEnforcementPort enforcementPort;
  late FocusCompletionEvaluator evaluator;
  late FocusSessionCoordinator coordinator;

  setUp(() {
    adhkarPort = InMemoryAdhkarCompletionPort();
    quranPort = InMemoryQuranReadingCompletionPort();
    enforcementPort = MockEnforcementPort();
    evaluator = const FocusCompletionEvaluator();

    coordinator = FocusSessionCoordinator(
      adhkarPort: adhkarPort,
      quranPort: quranPort,
      enforcementPort: enforcementPort,
      evaluator: evaluator,
    );
  });

  tearDown(() {
    coordinator.dispose();
    adhkarPort.dispose();
    quranPort.dispose();
  });

  group('Focus Mode Phase 1 — Comprehensive Edge Cases (8 Scenarios)', () {
    // -------------------------------------------------------------
    // Scenario 1: وصول حدث إتمام من sessionId قديم
    // -------------------------------------------------------------
    test('Scenario 1: Event from an old/stale sessionId is strictly rejected', () async {
      await coordinator.startSession(
        sessionId: 'session_active_2026',
        wardType: FocusWardType.morningAzkar,
      );

      // Event carrying a stale sessionId from a previous run
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 15,
          sessionId: 'session_old_expired_2025',
        ),
      );

      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(enforcementPort.stopCalls, equals(0));
    });

    // -------------------------------------------------------------
    // Scenario 2: وصول نفس حدث إتمام الذكر مرتين (Duplicate Keys)
    // -------------------------------------------------------------
    test('Scenario 2: Duplicate item completion does not falsely fulfill requirement', () async {
      await coordinator.startSession(
        sessionId: 'session_adhkar_keys',
        wardType: FocusWardType.morningAzkar,
      );

      final requiredKeys = {'zikr-A', 'zikr-B', 'zikr-C'};
      // User tapped zikr-A twice instead of completing zikr-B & zikr-C
      final duplicateKeys = {'zikr-A'};

      final event = AdhkarCompletionEvent(
        wardType: FocusWardType.morningAzkar,
        categoryKey: 'morning',
        completedItemKeys: duplicateKeys,
        requiredItemKeys: requiredKeys,
        isFullyCompleted: false,
        timestamp: DateTime.now(),
        sessionId: 'session_adhkar_keys',
      );

      adhkarPort.dispatchEvent(event);
      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(enforcementPort.stopCalls, equals(0));
    });

    // -------------------------------------------------------------
    // Scenario 3: وصول أحداث من نوع ورد مختلف (Ward Mismatch)
    // -------------------------------------------------------------
    test('Scenario 3: Events from a different ward type are ignored', () async {
      await coordinator.startSession(
        sessionId: 'session_morning_active',
        wardType: FocusWardType.morningAzkar,
      );

      // Event arriving from eveningAzkar while morning is active
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.eveningAzkar,
          categoryKey: 'evening',
          totalCount: 10,
        ),
      );

      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(enforcementPort.stopCalls, equals(0));
    });

    // -------------------------------------------------------------
    // Scenario 4: انتقال المستخدم إلى Background أثناء احتساب زمن صفحة القرآن
    // -------------------------------------------------------------
    test('Scenario 4: Quran dwell while app is in background is rejected', () async {
      await coordinator.startSession(
        sessionId: 'session_quran_bg',
        wardType: FocusWardType.quranReading,
        quranGoal: QuranReadingGoal.pageCount(1, minDurationPerPage: const Duration(seconds: 20)),
      );

      // Event recorded with isForeground == false
      quranPort.recordPageDwell(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 40),
      );
      // Directly dispatch an event simulating background state
      final bgEvent = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 40),
        timestamp: DateTime.now(),
        isForeground: false, // In Background!
        isScreenOn: true,
      );

      expect(evaluator.isPageDwellGenuine(
        goal: coordinator.state.quranGoal!,
        event: bgEvent,
      ), isFalse);

      expect(coordinator.state.status, equals(FocusSessionStatus.active));
    });

    // -------------------------------------------------------------
    // Scenario 5: إطفاء الشاشة أثناء المكوث
    // -------------------------------------------------------------
    test('Scenario 5: Quran dwell while screen is turned off is rejected', () {
      final goal = QuranReadingGoal.pageCount(1, minDurationPerPage: const Duration(seconds: 20));
      final screenOffEvent = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 60),
        timestamp: DateTime.now(),
        isForeground: true,
        isScreenOn: false, // Screen Locked/Off!
      );

      expect(evaluator.isPageDwellGenuine(
        goal: goal,
        event: screenOffEvent,
      ), isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 6: مغادرة الصفحة والعودة إليها دون احتسابها مرتين
    // -------------------------------------------------------------
    test('Scenario 6: Revisiting the same page multiple times does not count as multiple pages', () async {
      await coordinator.startSession(
        sessionId: 'session_quran_revisit',
        wardType: FocusWardType.quranReading,
        quranGoal: QuranReadingGoal.pageCount(2, minDurationPerPage: const Duration(seconds: 20)),
      );

      // Read Page 1 genuinely for 25s
      quranPort.recordPageDwell(pageNumber: 1, timeSpent: const Duration(seconds: 25));
      await pumpEventQueue();
      expect(coordinator.state.status, equals(FocusSessionStatus.active));

      // Leave Page 1, go to another screen, then return to Page 1 again for 30s
      quranPort.recordPageDwell(pageNumber: 1, timeSpent: const Duration(seconds: 30));
      await pumpEventQueue();

      // Session MUST still be active because target is 2 DISTINCT pages!
      expect(coordinator.state.status, equals(FocusSessionStatus.active));
      expect(enforcementPort.stopCalls, equals(0));

      // Now read Page 2 genuinely for 25s
      quranPort.recordPageDwell(pageNumber: 2, timeSpent: const Duration(seconds: 25));
      await pumpEventQueue();

      // Now target of 2 distinct pages is met
      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(enforcementPort.stopCalls, equals(1));
    });

    // -------------------------------------------------------------
    // Scenario 7: اكتمال الورد ووصول حدث آخر بعد تحويل الحالة إلى completed
    // -------------------------------------------------------------
    test('Scenario 7: Events arriving after session is completed are ignored cleanly', () async {
      await coordinator.startSession(
        sessionId: 'session_done_1',
        wardType: FocusWardType.morningAzkar,
      );

      // Complete session
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 5,
        ),
      );
      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(enforcementPort.stopCalls, equals(1));

      // Subsequent event arrives
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 5,
        ),
      );
      await pumpEventQueue();

      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(enforcementPort.stopCalls, equals(1)); // Still only 1 call
    });

    // -------------------------------------------------------------
    // Scenario 8: فشل Native Engine في إزالة الدرع بعد اكتمال الجلسة
    // -------------------------------------------------------------
    test('Scenario 8: Session becomes Completed even if enforcement stop fails, and flags failure', () async {
      enforcementPort.shouldStopFail = true; // Simulate native stop failure

      await coordinator.startSession(
        sessionId: 'session_enforcement_fail_test',
        wardType: FocusWardType.morningAzkar,
      );

      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: 'morning',
          totalCount: 10,
        ),
      );
      await pumpEventQueue();

      // Worship was genuinely finished, so state IS completed
      expect(coordinator.state.status, equals(FocusSessionStatus.completed));
      expect(coordinator.state.endTime, isNotNull);
      // But enforcement failure is recorded!
      expect(coordinator.state.enforcementStopFailed, isTrue);
      expect(enforcementPort.stopCalls, equals(1));
    });
  });
}
