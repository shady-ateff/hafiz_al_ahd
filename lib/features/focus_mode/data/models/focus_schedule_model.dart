import 'dart:convert';
import '../../domain/entities/focus_schedule.dart';
import '../../domain/entities/focus_ward_type.dart';
import '../../domain/entities/quran_reading_goal.dart';

class FocusScheduleModel {
  final String id;
  final String wardType;
  final String title;
  final int hour;
  final int minute;
  final String daysOfWeekJson;
  final int isEnabled;
  final int preNotificationMinutes;
  final String? quranGoalJson;
  final int? lastTriggeredAt;
  final int createdAt;
  final int updatedAt;

  const FocusScheduleModel({
    required this.id,
    required this.wardType,
    required this.title,
    required this.hour,
    required this.minute,
    required this.daysOfWeekJson,
    required this.isEnabled,
    required this.preNotificationMinutes,
    this.quranGoalJson,
    this.lastTriggeredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FocusScheduleModel.fromEntity(FocusSchedule entity) {
    return FocusScheduleModel(
      id: entity.id,
      wardType: entity.wardType.name,
      title: entity.title,
      hour: entity.hour,
      minute: entity.minute,
      daysOfWeekJson: jsonEncode(entity.daysOfWeek),
      isEnabled: entity.isEnabled ? 1 : 0,
      preNotificationMinutes: entity.preNotificationMinutes,
      quranGoalJson: entity.targetQuranGoal != null
          ? jsonEncode({
              'goalType': entity.targetQuranGoal!.goalType.name,
              'targetValue': entity.targetQuranGoal!.targetValue,
              'startValue': entity.targetQuranGoal!.startValue,
              'minDurationSeconds':
                  entity.targetQuranGoal!.minDurationPerPage.inSeconds,
            })
          : null,
      lastTriggeredAt: entity.lastTriggeredAt?.millisecondsSinceEpoch,
      createdAt: entity.createdAt.millisecondsSinceEpoch,
      updatedAt: entity.updatedAt.millisecondsSinceEpoch,
    );
  }

  FocusSchedule toEntity() {
    FocusWardType ward;
    try {
      ward = FocusWardType.values.byName(wardType);
    } catch (_) {
      ward = FocusWardType.morningAzkar;
    }

    List<int> days;
    try {
      final decoded = jsonDecode(daysOfWeekJson) as List<dynamic>;
      days = decoded.map((e) => e as int).toList();
    } catch (_) {
      days = const [1, 2, 3, 4, 5, 6, 7];
    }

    QuranReadingGoal? quranGoal;
    if (quranGoalJson != null && quranGoalJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(quranGoalJson!) as Map<String, dynamic>;
        quranGoal = QuranReadingGoal(
          goalType:
              QuranGoalType.values.byName(decoded['goalType'] as String),
          targetValue: decoded['targetValue'] as int,
          startValue: decoded['startValue'] as int?,
          minDurationPerPage: Duration(
              seconds: (decoded['minDurationSeconds'] as num?)?.toInt() ?? 20),
        );
      } catch (_) {
        quranGoal = null;
      }
    }

    return FocusSchedule(
      id: id,
      wardType: ward,
      title: title,
      hour: hour,
      minute: minute,
      daysOfWeek: days,
      isEnabled: isEnabled == 1,
      preNotificationMinutes: preNotificationMinutes,
      targetQuranGoal: quranGoal,
      lastTriggeredAt: lastTriggeredAt != null
          ? DateTime.fromMillisecondsSinceEpoch(lastTriggeredAt!)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ward_type': wardType,
      'title': title,
      'hour': hour,
      'minute': minute,
      'days_of_week': daysOfWeekJson,
      'is_enabled': isEnabled,
      'pre_notification_minutes': preNotificationMinutes,
      'quran_goal_json': quranGoalJson,
      'last_triggered_at': lastTriggeredAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory FocusScheduleModel.fromMap(Map<String, dynamic> map) {
    return FocusScheduleModel(
      id: map['id'] as String,
      wardType: map['ward_type'] as String,
      title: map['title'] as String,
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      daysOfWeekJson: map['days_of_week'] as String,
      isEnabled: (map['is_enabled'] as num).toInt(),
      preNotificationMinutes: (map['pre_notification_minutes'] as num).toInt(),
      quranGoalJson: map['quran_goal_json'] as String?,
      lastTriggeredAt: map['last_triggered_at'] as int?,
      createdAt: (map['created_at'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
    );
  }
}
