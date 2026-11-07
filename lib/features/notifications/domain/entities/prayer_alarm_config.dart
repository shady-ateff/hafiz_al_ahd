import 'package:flutter/foundation.dart';

/// Strongly typed identifiers for the five daily obligatory prayers.
enum PrayerId {
  fajr,
  dhuhr,
  asr,
  maghrib,
  isha;

  /// String key representation matching legacy and storage conventions.
  String get key => name;

  /// Safe deserialization from a string key.
  static PrayerId? fromKey(String? key) {
    if (key == null) return null;
    for (final id in PrayerId.values) {
      if (id.name == key.toLowerCase().trim()) {
        return id;
      }
    }
    return null;
  }
}

/// The alarm action type for a prayer.
enum PrayerAlarmType {
  /// Full-screen intent alarm with audio playback via package:alarm.
  alarm,

  /// High-priority notification with sound via flutter_local_notifications.
  notification,

  /// Disabled: no alarm or notification is scheduled for this prayer.
  off;

  /// String key representation.
  String get key => name;

  /// Safe deserialization from a string value with deterministic fallback.
  static PrayerAlarmType fromKey(String? key, {PrayerAlarmType fallback = PrayerAlarmType.alarm}) {
    if (key == null) return fallback;
    for (final type in PrayerAlarmType.values) {
      if (type.name == key.toLowerCase().trim()) {
        return type;
      }
    }
    return fallback;
  }
}

/// Immutable configuration for a single prayer alarm.
@immutable
class PrayerAlarmConfig {
  final PrayerId prayerId;
  final PrayerAlarmType alarmType;

  const PrayerAlarmConfig({
    required this.prayerId,
    required this.alarmType,
  });

  /// Creates a copy with optional updated fields.
  PrayerAlarmConfig copyWith({
    PrayerId? prayerId,
    PrayerAlarmType? alarmType,
  }) {
    return PrayerAlarmConfig(
      prayerId: prayerId ?? this.prayerId,
      alarmType: alarmType ?? this.alarmType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerAlarmConfig &&
        other.prayerId == prayerId &&
        other.alarmType == alarmType;
  }

  @override
  int get hashCode => Object.hash(prayerId, alarmType);

  @override
  String toString() => 'PrayerAlarmConfig(prayerId: ${prayerId.key}, alarmType: ${alarmType.key})';
}

