import 'focus_ward_type.dart';
import 'quran_reading_goal.dart';

/// Base class for all ward completion events emitted across the application.
abstract class WardCompletionEvent {
  final FocusWardType wardType;
  final DateTime timestamp;
  final String? sessionId;

  const WardCompletionEvent({
    required this.wardType,
    required this.timestamp,
    this.sessionId,
  });
}

/// Emitted when adhkar progress is reported or a category is completed.
/// Relies on unique item keys rather than mere counts to prevent counting duplicate items.
class AdhkarCompletionEvent extends WardCompletionEvent {
  final String categoryKey;
  final Set<String> completedItemKeys;
  final Set<String> requiredItemKeys;
  final bool isFullyCompleted;

  int get completedItemsCount => completedItemKeys.length;
  int get totalItemsCount => requiredItemKeys.length;

  const AdhkarCompletionEvent({
    required super.wardType,
    required this.categoryKey,
    required this.completedItemKeys,
    required this.requiredItemKeys,
    required this.isFullyCompleted,
    required super.timestamp,
    super.sessionId,
  });

  /// Factory for when an entire category is completed.
  factory AdhkarCompletionEvent.completed({
    required FocusWardType wardType,
    required String categoryKey,
    int? totalCount,
    Set<String>? itemKeys,
    String? sessionId,
  }) {
    final keys = itemKeys ??
        (totalCount != null
            ? List.generate(totalCount, (i) => '$categoryKey-item-$i').toSet()
            : <String>{});
    return AdhkarCompletionEvent(
      wardType: wardType,
      categoryKey: categoryKey,
      completedItemKeys: Set<String>.unmodifiable(keys),
      requiredItemKeys: Set<String>.unmodifiable(keys),
      isFullyCompleted: true,
      timestamp: DateTime.now(),
      sessionId: sessionId,
    );
  }

  /// Factory for incremental progress reporting.
  factory AdhkarCompletionEvent.progress({
    required FocusWardType wardType,
    required String categoryKey,
    required int completedCount,
    required int totalCount,
    Set<String>? completedKeys,
    Set<String>? requiredKeys,
    String? sessionId,
  }) {
    final reqKeys = requiredKeys ??
        List.generate(totalCount, (i) => '$categoryKey-item-$i').toSet();
    final compKeys = completedKeys ??
        List.generate(completedCount, (i) => '$categoryKey-item-$i').toSet();

    final isAllDone =
        compKeys.length >= reqKeys.length && compKeys.containsAll(reqKeys);

    return AdhkarCompletionEvent(
      wardType: wardType,
      categoryKey: categoryKey,
      completedItemKeys: Set<String>.unmodifiable(compKeys),
      requiredItemKeys: Set<String>.unmodifiable(reqKeys),
      isFullyCompleted: isAllDone,
      timestamp: DateTime.now(),
      sessionId: sessionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhkarCompletionEvent &&
          runtimeType == other.runtimeType &&
          wardType == other.wardType &&
          categoryKey == other.categoryKey &&
          sessionId == other.sessionId &&
          completedItemKeys.length == other.completedItemKeys.length &&
          completedItemKeys.containsAll(other.completedItemKeys) &&
          requiredItemKeys.length == other.requiredItemKeys.length &&
          requiredItemKeys.containsAll(other.requiredItemKeys) &&
          isFullyCompleted == other.isFullyCompleted;

  @override
  int get hashCode =>
      wardType.hashCode ^
      categoryKey.hashCode ^
      (sessionId?.hashCode ?? 0) ^
      completedItemKeys.length.hashCode ^
      requiredItemKeys.length.hashCode ^
      isFullyCompleted.hashCode;
}

/// Emitted when reading activity on a Quran page is recorded.
/// Carries explicit foreground and screen state flags to reject background dwell.
class QuranPageReadEvent {
  final int pageNumber;
  final Duration timeSpent;
  final DateTime timestamp;
  final bool isForeground;
  final bool isScreenOn;

  const QuranPageReadEvent({
    required this.pageNumber,
    required this.timeSpent,
    required this.timestamp,
    this.isForeground = true,
    this.isScreenOn = true,
  });

  bool get isEligibleForTracking => isForeground && isScreenOn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranPageReadEvent &&
          runtimeType == other.runtimeType &&
          pageNumber == other.pageNumber &&
          timeSpent == other.timeSpent &&
          isForeground == other.isForeground &&
          isScreenOn == other.isScreenOn;

  @override
  int get hashCode =>
      pageNumber.hashCode ^
      timeSpent.hashCode ^
      isForeground.hashCode ^
      isScreenOn.hashCode;
}

/// Emitted when a Quran reading goal is completely satisfied.
class QuranGoalCompletedEvent extends WardCompletionEvent {
  final QuranGoalType goalType;
  final int achievedTarget;
  final int totalPagesRead;
  final Duration totalReadingDuration;

  const QuranGoalCompletedEvent({
    required this.goalType,
    required this.achievedTarget,
    required this.totalPagesRead,
    required this.totalReadingDuration,
    required super.timestamp,
    super.sessionId,
  }) : super(wardType: FocusWardType.quranReading);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranGoalCompletedEvent &&
          runtimeType == other.runtimeType &&
          wardType == other.wardType &&
          sessionId == other.sessionId &&
          goalType == other.goalType &&
          achievedTarget == other.achievedTarget &&
          totalPagesRead == other.totalPagesRead &&
          totalReadingDuration == other.totalReadingDuration;

  @override
  int get hashCode =>
      wardType.hashCode ^
      (sessionId?.hashCode ?? 0) ^
      goalType.hashCode ^
      achievedTarget.hashCode ^
      totalPagesRead.hashCode ^
      totalReadingDuration.hashCode;
}
