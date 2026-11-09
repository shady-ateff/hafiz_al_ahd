import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

/// The pure scheduling decision for an individual prayer alert.
enum PrayerAlertDecision {
  /// A full-screen prayer alarm.
  alarm,

  /// A prayer notification with an audible alert.
  notification,

  /// No prayer alert should be scheduled.
  none;

  /// Pure mapping function from [PrayerAlarmConfig] to [PrayerAlertDecision].
  static PrayerAlertDecision fromConfig(PrayerAlarmConfig config) {
    switch (config.alarmType) {
      case PrayerAlarmType.alarm:
        return PrayerAlertDecision.alarm;
      case PrayerAlarmType.notification:
        return PrayerAlertDecision.notification;
      case PrayerAlarmType.off:
        return PrayerAlertDecision.none;
    }
  }
}

/// Convenience extension on [PrayerAlarmConfig] to obtain its desired [PrayerAlertDecision].
extension PrayerAlarmConfigDecisionX on PrayerAlarmConfig {
  PrayerAlertDecision get decision => PrayerAlertDecision.fromConfig(this);
}

