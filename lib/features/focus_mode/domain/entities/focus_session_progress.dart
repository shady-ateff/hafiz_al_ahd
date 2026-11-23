import 'quran_reading_goal.dart';

/// Full snapshot of progress made during an active Focus Mode session.
class FocusSessionProgress {
  final String sessionId;
  final Set<String> requiredItemKeys;
  final Set<String> completedItemKeys;
  final Set<int> readQuranPages;
  final Duration accumulatedQuranDuration;
  final int? lastCompletedPage;
  final QuranReadingGoal? quranGoalSnapshot;
  final int sessionVersion;
  final DateTime updatedAt;

  const FocusSessionProgress({
    required this.sessionId,
    this.requiredItemKeys = const <String>{},
    this.completedItemKeys = const <String>{},
    this.readQuranPages = const <int>{},
    this.accumulatedQuranDuration = Duration.zero,
    this.lastCompletedPage,
    this.quranGoalSnapshot,
    this.sessionVersion = 1,
    required this.updatedAt,
  });

  bool get isAzkarCompleted =>
      requiredItemKeys.isNotEmpty &&
      completedItemKeys.containsAll(requiredItemKeys);

  FocusSessionProgress copyWith({
    String? sessionId,
    Set<String>? requiredItemKeys,
    Set<String>? completedItemKeys,
    Set<int>? readQuranPages,
    Duration? accumulatedQuranDuration,
    int? lastCompletedPage,
    QuranReadingGoal? quranGoalSnapshot,
    int? sessionVersion,
    DateTime? updatedAt,
  }) {
    return FocusSessionProgress(
      sessionId: sessionId ?? this.sessionId,
      requiredItemKeys: requiredItemKeys ?? this.requiredItemKeys,
      completedItemKeys: completedItemKeys ?? this.completedItemKeys,
      readQuranPages: readQuranPages ?? this.readQuranPages,
      accumulatedQuranDuration:
          accumulatedQuranDuration ?? this.accumulatedQuranDuration,
      lastCompletedPage: lastCompletedPage ?? this.lastCompletedPage,
      quranGoalSnapshot: quranGoalSnapshot ?? this.quranGoalSnapshot,
      sessionVersion: sessionVersion ?? this.sessionVersion,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory FocusSessionProgress.initial({
    required String sessionId,
    Set<String>? requiredItemKeys,
    QuranReadingGoal? quranGoal,
  }) {
    return FocusSessionProgress(
      sessionId: sessionId,
      requiredItemKeys: requiredItemKeys ?? const <String>{},
      completedItemKeys: const <String>{},
      readQuranPages: const <int>{},
      accumulatedQuranDuration: Duration.zero,
      quranGoalSnapshot: quranGoal,
      sessionVersion: 1,
      updatedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusSessionProgress &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          requiredItemKeys.length == other.requiredItemKeys.length &&
          requiredItemKeys.containsAll(other.requiredItemKeys) &&
          completedItemKeys.length == other.completedItemKeys.length &&
          completedItemKeys.containsAll(other.completedItemKeys) &&
          readQuranPages.length == other.readQuranPages.length &&
          readQuranPages.containsAll(other.readQuranPages) &&
          accumulatedQuranDuration == other.accumulatedQuranDuration &&
          lastCompletedPage == other.lastCompletedPage &&
          quranGoalSnapshot == other.quranGoalSnapshot &&
          sessionVersion == other.sessionVersion;

  @override
  int get hashCode =>
      sessionId.hashCode ^
      requiredItemKeys.length.hashCode ^
      completedItemKeys.length.hashCode ^
      readQuranPages.length.hashCode ^
      accumulatedQuranDuration.hashCode ^
      (lastCompletedPage?.hashCode ?? 0) ^
      (quranGoalSnapshot?.hashCode ?? 0) ^
      sessionVersion.hashCode;
}
