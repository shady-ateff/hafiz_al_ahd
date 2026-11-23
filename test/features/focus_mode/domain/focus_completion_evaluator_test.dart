import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_state.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/ward_completion_event.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_completion_evaluator.dart';

void main() {
  late FocusCompletionEvaluator evaluator;

  setUp(() {
    evaluator = const FocusCompletionEvaluator();
  });

  group('FocusCompletionEvaluator - Adhkar Evaluation', () {
    final activeMorningSession = FocusSessionState(
      sessionId: 'session_morning_100',
      wardType: FocusWardType.morningAzkar,
      status: FocusSessionStatus.active,
      startTime: DateTime.now(),
    );

    test('should return true when event matches ward and is fully completed with unique keys', () {
      final keys = {'zikr-1', 'zikr-2', 'zikr-3'};
      final event = AdhkarCompletionEvent(
        wardType: FocusWardType.morningAzkar,
        categoryKey: 'morning',
        completedItemKeys: keys,
        requiredItemKeys: keys,
        isFullyCompleted: true,
        timestamp: DateTime.now(),
        sessionId: 'session_morning_100',
      );

      final result = evaluator.evaluateAdhkarCompletion(
        session: activeMorningSession,
        event: event,
      );

      expect(result, isTrue);
    });

    test('should return false when adhkar completion is partial', () {
      final reqKeys = {'zikr-1', 'zikr-2', 'zikr-3'};
      final compKeys = {'zikr-1', 'zikr-2'}; // Missing zikr-3

      final event = AdhkarCompletionEvent(
        wardType: FocusWardType.morningAzkar,
        categoryKey: 'morning',
        completedItemKeys: compKeys,
        requiredItemKeys: reqKeys,
        isFullyCompleted: false,
        timestamp: DateTime.now(),
      );

      final result = evaluator.evaluateAdhkarCompletion(
        session: activeMorningSession,
        event: event,
      );

      expect(result, isFalse);
    });

    test('should return false when there is a ward mismatch', () {
      final event = AdhkarCompletionEvent.completed(
        wardType: FocusWardType.eveningAzkar,
        categoryKey: 'evening',
        totalCount: 12,
      );

      final result = evaluator.evaluateAdhkarCompletion(
        session: activeMorningSession,
        event: event,
      );

      expect(result, isFalse);
    });

    test('should return false when event comes from an old sessionId', () {
      final event = AdhkarCompletionEvent.completed(
        wardType: FocusWardType.morningAzkar,
        categoryKey: 'morning',
        totalCount: 15,
        sessionId: 'old_expired_session_999',
      );

      final result = evaluator.evaluateAdhkarCompletion(
        session: activeMorningSession,
        event: event,
      );

      expect(result, isFalse);
    });

    test('should return false when session is not active or snoozed', () {
      final idleSession = activeMorningSession.copyWith(
        status: FocusSessionStatus.idle,
      );
      final cancelledSession = activeMorningSession.copyWith(
        status: FocusSessionStatus.cancelled,
      );
      final event = AdhkarCompletionEvent.completed(
        wardType: FocusWardType.morningAzkar,
        categoryKey: 'morning',
        totalCount: 15,
      );

      expect(
        evaluator.evaluateAdhkarCompletion(session: idleSession, event: event),
        isFalse,
      );
      expect(
        evaluator.evaluateAdhkarCompletion(session: cancelledSession, event: event),
        isFalse,
      );
    });
  });

  group('FocusCompletionEvaluator - Quran Evaluation & Lifecycle Checks', () {
    final goal = QuranReadingGoal.pageCount(2, minDurationPerPage: const Duration(seconds: 20));

    test('isPageDwellGenuine rejects when app is in background', () {
      final event = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 30),
        timestamp: DateTime.now(),
        isForeground: false, // in Background
        isScreenOn: true,
      );

      expect(evaluator.isPageDwellGenuine(goal: goal, event: event), isFalse);
    });

    test('isPageDwellGenuine rejects when screen is turned off', () {
      final event = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 30),
        timestamp: DateTime.now(),
        isForeground: true,
        isScreenOn: false, // Screen locked
      );

      expect(evaluator.isPageDwellGenuine(goal: goal, event: event), isFalse);
    });

    test('isPageDwellGenuine rejects superficial page flipping under 20s', () {
      final event = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 3),
        timestamp: DateTime.now(),
      );

      expect(evaluator.isPageDwellGenuine(goal: goal, event: event), isFalse);
    });

    test('isPageDwellGenuine accepts dwell time meeting minimum duration in foreground', () {
      final event = QuranPageReadEvent(
        pageNumber: 1,
        timeSpent: const Duration(seconds: 25),
        timestamp: DateTime.now(),
        isForeground: true,
        isScreenOn: true,
      );

      expect(evaluator.isPageDwellGenuine(goal: goal, event: event), isTrue);
    });
  });
}
