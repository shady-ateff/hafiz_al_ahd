import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

/// Data model representation of [PrayerAlarmConfig] supporting JSON serialization.
class PrayerAlarmConfigModel extends PrayerAlarmConfig {
  const PrayerAlarmConfigModel({
    required super.prayerId,
    required super.alarmType,
    super.audioSource,
    super.volume,
    super.isVibrationEnabled,
  });

  /// Creates a model from a domain entity.
  factory PrayerAlarmConfigModel.fromEntity(PrayerAlarmConfig entity) {
    return PrayerAlarmConfigModel(
      prayerId: entity.prayerId,
      alarmType: entity.alarmType,
      audioSource: entity.audioSource,
      volume: entity.volume,
      isVibrationEnabled: entity.isVibrationEnabled,
    );
  }

  /// Deserializes a model from a JSON map with safe fallbacks.
  factory PrayerAlarmConfigModel.fromJson(Map<String, dynamic> json) {
    final prayerId = PrayerId.fromKey(json['prayerId'] as String?) ?? PrayerId.fajr;
    final alarmType = PrayerAlarmType.fromKey(json['alarmType'] as String?);

    AudioSourceConfig? audioSource;
    if (json['audioSource'] != null && json['audioSource'] is Map<String, dynamic>) {
      audioSource = AudioSourceConfig.fromJson(
        json['audioSource'] as Map<String, dynamic>,
        isFajr: prayerId == PrayerId.fajr,
      );
    }

    final double? volume = json['volume'] != null
        ? (json['volume'] as num).toDouble().clamp(0.1, 1.0)
        : null;
    final bool? isVibrationEnabled = json['isVibrationEnabled'] as bool?;

    return PrayerAlarmConfigModel(
      prayerId: prayerId,
      alarmType: alarmType,
      audioSource: audioSource,
      volume: volume,
      isVibrationEnabled: isVibrationEnabled,
    );
  }

  /// Serializes the model to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'prayerId': prayerId.key,
      'alarmType': alarmType.key,
      'audioSource': audioSource.toJson(),
      'volume': volume,
      'isVibrationEnabled': isVibrationEnabled,
    };
  }
}
