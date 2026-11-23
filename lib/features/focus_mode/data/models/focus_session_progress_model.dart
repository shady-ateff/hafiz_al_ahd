import 'dart:convert';
import '../../domain/entities/focus_session_progress.dart';
import '../../domain/entities/quran_reading_goal.dart';

class FocusSessionProgressModel extends FocusSessionProgress {
  const FocusSessionProgressModel({
    required super.sessionId,
    super.requiredItemKeys,
    super.completedItemKeys,
    super.readQuranPages,
    super.accumulatedQuranDuration,
    super.lastCompletedPage,
    super.quranGoalSnapshot,
    super.sessionVersion,
    required super.updatedAt,
  });

  factory FocusSessionProgressModel.fromEntity(FocusSessionProgress entity) {
    return FocusSessionProgressModel(
      sessionId: entity.sessionId,
      requiredItemKeys: entity.requiredItemKeys,
      completedItemKeys: entity.completedItemKeys,
      readQuranPages: entity.readQuranPages,
      accumulatedQuranDuration: entity.accumulatedQuranDuration,
      lastCompletedPage: entity.lastCompletedPage,
      quranGoalSnapshot: entity.quranGoalSnapshot,
      sessionVersion: entity.sessionVersion,
      updatedAt: entity.updatedAt,
    );
  }

  factory FocusSessionProgressModel.fromDbMap(Map<String, dynamic> map) {
    Set<String> requiredKeys = const {};
    final reqJson = map['required_item_keys'] as String?;
    if (reqJson != null && reqJson.isNotEmpty) {
      try {
        final list = jsonDecode(reqJson) as List;
        requiredKeys = list.map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    Set<String> completedKeys = const {};
    final compJson = map['completed_item_keys'] as String?;
    if (compJson != null && compJson.isNotEmpty) {
      try {
        final list = jsonDecode(compJson) as List;
        completedKeys = list.map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    Set<int> readPages = const {};
    final pagesJson = map['read_quran_pages'] as String?;
    if (pagesJson != null && pagesJson.isNotEmpty) {
      try {
        final list = jsonDecode(pagesJson) as List;
        readPages = list.map((e) => (e as num).toInt()).toSet();
      } catch (_) {}
    }

    QuranReadingGoal? quranGoal;
    final goalJsonStr = map['quran_goal_snapshot_json'] as String?;
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

    final durationMs = map['accumulated_quran_duration_ms'] as int? ?? 0;
    final updatedAtEpoch = map['updated_at'] as int? ?? 0;

    return FocusSessionProgressModel(
      sessionId: map['session_id'] as String? ?? '',
      requiredItemKeys: requiredKeys,
      completedItemKeys: completedKeys,
      readQuranPages: readPages,
      accumulatedQuranDuration: Duration(milliseconds: durationMs),
      lastCompletedPage: map['last_completed_page'] as int?,
      quranGoalSnapshot: quranGoal,
      sessionVersion: map['session_version'] as int? ?? 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtEpoch),
    );
  }

  Map<String, dynamic> toDbMap() {
    String? goalJson;
    if (quranGoalSnapshot != null) {
      goalJson = jsonEncode({
        'goalType': quranGoalSnapshot!.goalType.name,
        'targetValue': quranGoalSnapshot!.targetValue,
        'startValue': quranGoalSnapshot!.startValue,
        'minDurationSeconds': quranGoalSnapshot!.minDurationPerPage.inSeconds,
      });
    }

    return {
      'session_id': sessionId,
      'required_item_keys': jsonEncode(requiredItemKeys.toList()),
      'completed_item_keys': jsonEncode(completedItemKeys.toList()),
      'read_quran_pages': jsonEncode(readQuranPages.toList()),
      'accumulated_quran_duration_ms': accumulatedQuranDuration.inMilliseconds,
      'last_completed_page': lastCompletedPage,
      'quran_goal_snapshot_json': goalJson,
      'session_version': sessionVersion,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }
}
