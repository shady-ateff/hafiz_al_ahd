/// Defines the specific reading goal for a Quran Focus session.
enum QuranGoalType {
  pages,
  surah,
  juzHizb,
  ayahRange,
}

class QuranReadingGoal {
  final QuranGoalType goalType;

  /// Target count of pages, or surah number, or juz/hizb number.
  final int targetValue;

  /// Optional starting page/ayah for range goals.
  final int? startValue;

  /// Minimum time required to consider reading genuine on a single page
  /// (preventing superficial scrolling/flipping). Default is 20 seconds.
  final Duration minDurationPerPage;

  const QuranReadingGoal({
    required this.goalType,
    required this.targetValue,
    this.startValue,
    this.minDurationPerPage = const Duration(seconds: 20),
  });

  /// Factory for a simple page-count goal (e.g. read 2 pages)
  factory QuranReadingGoal.pageCount(int pages, {Duration? minDurationPerPage}) {
    return QuranReadingGoal(
      goalType: QuranGoalType.pages,
      targetValue: pages,
      minDurationPerPage: minDurationPerPage ?? const Duration(seconds: 20),
    );
  }

  /// Factory for completing a specific Surah (e.g. Surah Al-Kahf)
  factory QuranReadingGoal.surah(int surahNumber, {Duration? minDurationPerPage}) {
    return QuranReadingGoal(
      goalType: QuranGoalType.surah,
      targetValue: surahNumber,
      minDurationPerPage: minDurationPerPage ?? const Duration(seconds: 30),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranReadingGoal &&
          runtimeType == other.runtimeType &&
          goalType == other.goalType &&
          targetValue == other.targetValue &&
          startValue == other.startValue &&
          minDurationPerPage == other.minDurationPerPage;

  @override
  int get hashCode =>
      goalType.hashCode ^
      targetValue.hashCode ^
      (startValue?.hashCode ?? 0) ^
      minDurationPerPage.hashCode;
}
