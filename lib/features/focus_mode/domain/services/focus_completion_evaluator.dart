import '../entities/focus_session_state.dart';
import '../entities/focus_ward_type.dart';
import '../entities/quran_reading_goal.dart';
import '../entities/ward_completion_event.dart';

/// Pure domain service responsible for evaluating completion rules.
/// Contains ZERO Flutter or presentation dependencies.
class FocusCompletionEvaluator {
  const FocusCompletionEvaluator();

  /// Evaluates whether an [AdhkarCompletionEvent] satisfies the completion criteria
  /// of the current [FocusSessionState].
  ///
  /// Enforces:
  /// 1. Active or snoozed session state.
  /// 2. Session ID correlation (rejects events from stale sessions).
  /// 3. Ward type and category key matching.
  /// 4. Unique item keys completeness: [completedItemKeys] must contain all [requiredItemKeys].
  bool evaluateAdhkarCompletion({
    required FocusSessionState session,
    required AdhkarCompletionEvent event,
  }) {
    if (!session.isActive && !session.isSnoozed) {
      return false;
    }

    // Old or mismatched sessionId rejection
    if (event.sessionId != null &&
        session.sessionId.isNotEmpty &&
        event.sessionId != session.sessionId) {
      return false;
    }

    // Ward mismatch check: active ward must match event ward
    if (session.wardType != event.wardType &&
        event.wardType != FocusWardType.custom &&
        session.wardType != FocusWardType.custom) {
      return false;
    }

    // Category key validation against ward definition
    if (session.wardType.categoryKey != event.categoryKey &&
        session.wardType != FocusWardType.custom &&
        event.categoryKey != 'custom') {
      return false;
    }

    // Completeness check using unique item keys
    if (!event.isFullyCompleted) {
      return false;
    }

    if (event.requiredItemKeys.isEmpty ||
        !event.completedItemKeys.containsAll(event.requiredItemKeys)) {
      return false;
    }

    return true;
  }

  /// Evaluates whether a recorded page dwell qualifies as genuine Quran reading.
  ///
  /// Rejects dwell if:
  /// - The app is not in the Foreground (`isForeground == false`).
  /// - The device screen is turned off (`isScreenOn == false`).
  /// - Dwell duration is below [minDurationPerPage].
  bool isPageDwellGenuine({
    required QuranReadingGoal goal,
    required QuranPageReadEvent event,
  }) {
    if (!event.isEligibleForTracking) {
      return false;
    }

    return event.timeSpent >= goal.minDurationPerPage;
  }

  /// Evaluates whether accumulated Quran reading satisfies the session's [QuranReadingGoal].
  ///
  /// [uniquePagesCount] must represent distinct pages (no duplicate counting).
  bool evaluateQuranGoalCompletion({
    required FocusSessionState session,
    required int uniquePagesCount,
    required Duration totalGenuineDuration,
    int? completedSurahNumber,
    String? eventSessionId,
  }) {
    if (!session.isActive && !session.isSnoozed) {
      return false;
    }

    // Old or mismatched sessionId rejection
    if (eventSessionId != null &&
        session.sessionId.isNotEmpty &&
        eventSessionId != session.sessionId) {
      return false;
    }

    if (session.wardType != FocusWardType.quranReading) {
      return false;
    }

    final goal = session.quranGoal;
    if (goal == null) {
      // Default fallback: at least 1 page read
      return uniquePagesCount >= 1;
    }

    switch (goal.goalType) {
      case QuranGoalType.pages:
        return uniquePagesCount >= goal.targetValue;

      case QuranGoalType.surah:
        return completedSurahNumber != null &&
            completedSurahNumber == goal.targetValue;

      case QuranGoalType.juzHizb:
      case QuranGoalType.ayahRange:
        return uniquePagesCount >= goal.targetValue;
    }
  }
}
