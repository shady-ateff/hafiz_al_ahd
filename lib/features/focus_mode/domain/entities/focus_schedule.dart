import 'package:equatable/equatable.dart';
import 'focus_ward_type.dart';
import 'quran_reading_goal.dart';

/// Represents a scheduled focus session rule.
class FocusSchedule extends Equatable {
  final String id;
  final FocusWardType wardType;
  final String title;
  final int hour; // 0..23
  final int minute; // 0..59
  final List<int> daysOfWeek; // 1 = Monday ... 7 = Sunday (DateTime.monday ... sunday)
  final bool isEnabled;
  final int preNotificationMinutes;
  final QuranReadingGoal? targetQuranGoal;
  final DateTime? lastTriggeredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FocusSchedule({
    required this.id,
    required this.wardType,
    required this.title,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    this.isEnabled = true,
    this.preNotificationMinutes = 0,
    this.targetQuranGoal,
    this.lastTriggeredAt,
    required this.createdAt,
    required this.updatedAt,
  })  : assert(hour >= 0 && hour <= 23, 'Hour must be between 0 and 23'),
        assert(minute >= 0 && minute <= 59, 'Minute must be between 0 and 59'),
        assert(daysOfWeek.length > 0, 'Must specify at least one day of the week');

  /// Creates a daily schedule helper
  factory FocusSchedule.daily({
    required String id,
    required FocusWardType wardType,
    required String title,
    required int hour,
    required int minute,
    bool isEnabled = true,
    int preNotificationMinutes = 0,
    QuranReadingGoal? targetQuranGoal,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return FocusSchedule(
      id: id,
      wardType: wardType,
      title: title,
      hour: hour,
      minute: minute,
      daysOfWeek: const [
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
        DateTime.sunday,
      ],
      isEnabled: isEnabled,
      preNotificationMinutes: preNotificationMinutes,
      targetQuranGoal: targetQuranGoal,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  FocusSchedule copyWith({
    String? id,
    FocusWardType? wardType,
    String? title,
    int? hour,
    int? minute,
    List<int>? daysOfWeek,
    bool? isEnabled,
    int? preNotificationMinutes,
    QuranReadingGoal? targetQuranGoal,
    DateTime? lastTriggeredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FocusSchedule(
      id: id ?? this.id,
      wardType: wardType ?? this.wardType,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      isEnabled: isEnabled ?? this.isEnabled,
      preNotificationMinutes:
          preNotificationMinutes ?? this.preNotificationMinutes,
      targetQuranGoal: targetQuranGoal ?? this.targetQuranGoal,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        wardType,
        title,
        hour,
        minute,
        daysOfWeek,
        isEnabled,
        preNotificationMinutes,
        targetQuranGoal,
        lastTriggeredAt,
        createdAt,
        updatedAt,
      ];
}
