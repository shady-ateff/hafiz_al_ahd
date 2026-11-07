import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

/// Data model representation of [PrayerAlarmConfig] supporting JSON serialization.
class PrayerAlarmConfigModel extends PrayerAlarmConfig {
  const PrayerAlarmConfigModel({
    required super.prayerId,
    required super.alarmType,
  });

  /// Creates a model from a domain entity.
  factory PrayerAlarmConfigModel.fromEntity(PrayerAlarmConfig entity) {
    return PrayerAlarmConfigModel(
      prayerId: entity.prayerId,
      alarmType: entity.alarmType,
    );
  }

  /// Deserializes a model from a JSON map with safe fallbacks.
  factory PrayerAlarmConfigModel.fromJson(Map<String, dynamic> json) {
    final prayerId = PrayerId.fromKey(json['prayerId'] as String?) ?? PrayerId.fajr;
    final alarmType = PrayerAlarmType.fromKey(json['alarmType'] as String?);
    return PrayerAlarmConfigModel(
      prayerId: prayerId,
      alarmType: alarmType,
    );
  }

  /// Serializes the model to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'prayerId': prayerId.key,
      'alarmType': alarmType.key,
    };
  }
}

