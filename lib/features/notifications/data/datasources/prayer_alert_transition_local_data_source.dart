import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alert_transition_record.dart';

abstract class BasePrayerAlertTransitionLocalDataSource {
  Future<PrayerAlertTransitionRecord?> getRecord(PrayerId prayerId);
  Future<Map<PrayerId, PrayerAlertTransitionRecord>> getAllRecords();
  Future<void> saveRecord(PrayerAlertTransitionRecord record);
  Future<void> deleteRecord(PrayerId prayerId);
  Future<void> clearAllRecords();
}

class PrayerAlertTransitionLocalDataSourceImpl implements BasePrayerAlertTransitionLocalDataSource {
  final SharedPreferences prefs;

  static String transitionKey(PrayerId prayerId) => 'prayer_alert_transition_${prayerId.key}';

  PrayerAlertTransitionLocalDataSourceImpl({required this.prefs});

  @override
  Future<PrayerAlertTransitionRecord?> getRecord(PrayerId prayerId) async {
    final raw = prefs.getString(transitionKey(prayerId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return PrayerAlertTransitionRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<PrayerId, PrayerAlertTransitionRecord>> getAllRecords() async {
    final Map<PrayerId, PrayerAlertTransitionRecord> result = {};
    for (final id in PrayerId.values) {
      final record = await getRecord(id);
      if (record != null) {
        result[id] = record;
      }
    }
    return result;
  }

  @override
  Future<void> saveRecord(PrayerAlertTransitionRecord record) async {
    final encoded = json.encode(record.toJson());
    await prefs.setString(transitionKey(record.prayerId), encoded);
  }

  @override
  Future<void> deleteRecord(PrayerId prayerId) async {
    await prefs.remove(transitionKey(prayerId));
  }

  @override
  Future<void> clearAllRecords() async {
    for (final id in PrayerId.values) {
      await prefs.remove(transitionKey(id));
    }
  }
}

