import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';

/// Strongly typed identifiers for the five daily obligatory prayers.
enum PrayerId {
  fajr,
  dhuhr,
  asr,
  maghrib,
  isha;

  /// String key representation matching legacy and storage conventions.
  String get key => name;

  /// Arabic display name for user-facing presentations, alarms, and notifications.
  String get arabicName {
    switch (this) {
      case PrayerId.fajr:
        return 'الفجر';
      case PrayerId.dhuhr:
        return 'الظهر';
      case PrayerId.asr:
        return 'العصر';
      case PrayerId.maghrib:
        return 'المغرب';
      case PrayerId.isha:
        return 'العشاء';
    }
  }

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
  final AudioSourceConfig? _audioSource;
  final double? volume; // null = inherit global adhan_volume, 0.1 to 1.0 = override
  final bool? isVibrationEnabled; // null = inherit global, true/false = per-prayer override

  const PrayerAlarmConfig({
    required this.prayerId,
    required this.alarmType,
    AudioSourceConfig? audioSource,
    this.volume,
    this.isVibrationEnabled,
  }) : _audioSource = audioSource;

  /// Audio source resolving prayer-specific defaults (Fajr vs General) when unspecified.
  AudioSourceConfig get audioSource =>
      _audioSource ?? AudioSourceConfig.defaultBuiltInFallback(isFajr: prayerId == PrayerId.fajr);

  /// Whether this prayer has an explicit audio source override configured.
  bool get hasAudioOverride =>
      _audioSource != null &&
      _audioSource.id != AudioSourceConfig.defaultMishary.id &&
      _audioSource.id != 'builtIn:default_general' &&
      _audioSource.id != 'builtIn:default_fajr';

  /// Returns the explicit audio source override, or null if inheriting global default.
  AudioSourceConfig? get audioSourceOverride => _audioSource;

  /// Factory constructor to ensure prayer-appropriate default audio when unspecified.
  factory PrayerAlarmConfig.withDefaultAudio({
    required PrayerId prayerId,
    required PrayerAlarmType alarmType,
    AudioSourceConfig? audioSource,
    double? volume,
    bool? isVibrationEnabled,
  }) {
    return PrayerAlarmConfig(
      prayerId: prayerId,
      alarmType: alarmType,
      audioSource: audioSource ?? AudioSourceConfig.defaultBuiltInFallback(isFajr: prayerId == PrayerId.fajr),
      volume: volume?.clamp(0.1, 1.0).toDouble(),
      isVibrationEnabled: isVibrationEnabled,
    );
  }

  /// Creates a copy with optional updated fields.
  PrayerAlarmConfig copyWith({
    PrayerId? prayerId,
    PrayerAlarmType? alarmType,
    AudioSourceConfig? audioSource,
    bool clearAudioOverride = false,
    double? volume,
    bool clearVolumeOverride = false,
    bool? isVibrationEnabled,
    bool clearVibrationOverride = false,
  }) {
    return PrayerAlarmConfig(
      prayerId: prayerId ?? this.prayerId,
      alarmType: alarmType ?? this.alarmType,
      audioSource: clearAudioOverride ? null : (audioSource ?? _audioSource),
      volume: clearVolumeOverride
          ? null
          : (volume != null ? volume.clamp(0.1, 1.0).toDouble() : this.volume),
      isVibrationEnabled: clearVibrationOverride
          ? null
          : (isVibrationEnabled ?? this.isVibrationEnabled),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerAlarmConfig &&
        other.prayerId == prayerId &&
        other.alarmType == alarmType &&
        other.audioSource == audioSource &&
        other.volume == volume &&
        other.isVibrationEnabled == isVibrationEnabled;
  }

  @override
  int get hashCode => Object.hash(
        prayerId,
        alarmType,
        audioSource,
        volume,
        isVibrationEnabled,
      );

  @override
  String toString() =>
      'PrayerAlarmConfig(prayerId: ${prayerId.key}, alarmType: ${alarmType.key}, audio: ${audioSource.id}, vol: $volume, vib: $isVibrationEnabled)';
}
