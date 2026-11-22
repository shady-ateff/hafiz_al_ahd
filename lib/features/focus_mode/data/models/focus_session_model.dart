import 'dart:convert';
import '../../domain/entities/focus_session_state.dart';
import '../../domain/entities/focus_session_status.dart';
import '../../domain/entities/focus_ward_type.dart';
import '../../domain/entities/quran_reading_goal.dart';

class FocusSessionModel extends FocusSessionState {
  const FocusSessionModel({
    required super.sessionId,
    required super.wardType,
    required super.status,
    required super.startTime,
    super.endTime,
    super.snoozeCount,
    super.maxSnoozeCount,
    super.quranGoal,
    super.interruptionReason,
    super.enforcementStopFailed,
  });

  factory FocusSessionModel.fromEntity(FocusSessionState entity) {
    return FocusSessionModel(
      sessionId: entity.sessionId,
      wardType: entity.wardType,
      status: entity.status,
      startTime: entity.startTime,
      endTime: entity.endTime,
      snoozeCount: entity.snoozeCount,
      maxSnoozeCount: entity.maxSnoozeCount,
      quranGoal: entity.quranGoal,
      interruptionReason: entity.interruptionReason,
      enforcementStopFailed: entity.enforcementStopFailed,
    );
  }

  factory FocusSessionModel.fromDbMap(Map<String, dynamic> map) {
    FocusWardType wardType = FocusWardType.morningAzkar;
    final wardStr = map['ward_type'] as String?;
    if (wardStr != null) {
      for (final w in FocusWardType.values) {
        if (w.name == wardStr) {
          wardType = w;
          break;
        }
      }
    }

    FocusSessionStatus status = FocusSessionStatus.idle;
    final statusStr = map['status'] as String?;
    if (statusStr != null) {
      for (final s in FocusSessionStatus.values) {
        if (s.name == statusStr) {
          status = s;
          break;
        }
      }
    }

    QuranReadingGoal? quranGoal;
    final goalJsonStr = map['quran_goal_json'] as String?;
    if (goalJsonStr != null && goalJsonStr.isNotEmpty) {
      try {
        final goalMap = jsonDecode(goalJsonStr) as Map<String, dynamic>;
        final goalTypeStr = goalMap['goalType'] as String?;
        QuranGoalType goalType = QuranGoalType.pages;
        for (final gt in QuranGoalType.values) {
          if (gt.name == goalTypeStr) {
            goalType = gt;
            break;
          }
        }
        quranGoal = QuranReadingGoal(
          goalType: goalType,
          targetValue: goalMap['targetValue'] as int? ?? 1,
          startValue: goalMap['startValue'] as int?,
          minDurationPerPage: Duration(
            seconds: goalMap['minDurationSeconds'] as int? ?? 20,
          ),
        );
      } catch (_) {}
    }

    final startTimeEpoch = map['start_time'] as int? ?? 0;
    final endTimeEpoch = map['end_time'] as int?;

    return FocusSessionModel(
      sessionId: map['session_id'] as String? ?? '',
      wardType: wardType,
      status: status,
      startTime: DateTime.fromMillisecondsSinceEpoch(startTimeEpoch),
      endTime: endTimeEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(endTimeEpoch)
          : null,
      snoozeCount: map['snooze_count'] as int? ?? 0,
      maxSnoozeCount: map['max_snooze_count'] as int? ?? 2,
      quranGoal: quranGoal,
      interruptionReason: map['interruption_reason'] as String?,
      enforcementStopFailed:
          (map['enforcement_stop_failed'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toDbMap({int isActive = 1}) {
    String? goalJson;
    if (quranGoal != null) {
      goalJson = jsonEncode({
        'goalType': quranGoal!.goalType.name,
        'targetValue': quranGoal!.targetValue,
        'startValue': quranGoal!.startValue,
        'minDurationSeconds': quranGoal!.minDurationPerPage.inSeconds,
      });
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return {
      'session_id': sessionId,
      'ward_type': wardType.name,
      'status': status.name,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'snooze_count': snoozeCount,
      'max_snooze_count': maxSnoozeCount,
      'interruption_reason': interruptionReason,
      'enforcement_stop_failed': enforcementStopFailed ? 1 : 0,
      'quran_goal_json': goalJson,
      'is_active': isActive,
      'created_at': startTime.millisecondsSinceEpoch,
      'updated_at': now,
    };
  }
}
