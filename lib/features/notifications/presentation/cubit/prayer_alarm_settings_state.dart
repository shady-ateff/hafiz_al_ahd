import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alert_transition_record.dart';

enum SettingsStatus { initial, loading, loaded, error }

class PrayerAlarmSettingsState extends Equatable {
  static const AudioSourceConfig defaultGeneralAudio = AudioSourceConfig.defaultMishary;

  final SettingsStatus status;
  final Map<PrayerId, PrayerAlarmConfig> configs;
  final Map<PrayerId, PrayerAlertTransitionRecord> activeTransitions;
  final double globalAdhanVolume;
  final bool isGlobalAdhanVibrationEnabled;
  final AudioSourceConfig globalAudioSource;
  final AudioSourceConfig? playingPreviewSource;
  final bool isPreviewPlaying;
  final bool isUpdatingAllPrayers;
  final String? errorMessage;
  final String? infoMessage;

  const PrayerAlarmSettingsState({
    this.status = SettingsStatus.initial,
    this.configs = const {},
    this.activeTransitions = const {},
    this.globalAdhanVolume = 1.0,
    this.isGlobalAdhanVibrationEnabled = true,
    this.globalAudioSource = defaultGeneralAudio,
    this.playingPreviewSource,
    this.isPreviewPlaying = false,
    this.isUpdatingAllPrayers = false,
    this.errorMessage,
    this.infoMessage,
  });

  /// Resolves the effective operational mode for a prayer,
  /// prioritizing active transitions over persisted configuration.
  PrayerAlarmType getEffectiveMode(PrayerId prayerId) {
    final transition = activeTransitions[prayerId];
    if (transition != null && transition.status != TransitionStatus.completed) {
      return transition.targetMode;
    }
    return configs[prayerId]?.alarmType ?? PrayerAlarmType.alarm;
  }

  /// Resolves the effective volume for a prayer (override or global inheritance).
  double getEffectiveVolume(PrayerId prayerId) {
    return configs[prayerId]?.volume ?? globalAdhanVolume;
  }

  /// Resolves the effective vibration for a prayer (override or global inheritance).
  bool getEffectiveVibration(PrayerId prayerId) {
    return configs[prayerId]?.isVibrationEnabled ?? isGlobalAdhanVibrationEnabled;
  }

  /// Resolves the effective audio source for a prayer (override or global inheritance).
  AudioSourceConfig getEffectiveAudioSource(PrayerId prayerId) {
    final config = configs[prayerId];
    if (config != null && config.hasAudioOverride) {
      return config.audioSource;
    }
    return globalAudioSource;
  }

  /// Whether all 5 prayers are set to full alarm.
  bool get allPrayersAreAlarm =>
      PrayerId.values.every((id) => getEffectiveMode(id) == PrayerAlarmType.alarm);

  /// Whether all 5 prayers are set to simple notification.
  bool get allPrayersAreNotification =>
      PrayerId.values.every((id) => getEffectiveMode(id) == PrayerAlarmType.notification);

  /// Whether all 5 prayers are turned off.
  bool get allPrayersAreOff =>
      PrayerId.values.every((id) => getEffectiveMode(id) == PrayerAlarmType.off);

  /// Whether prayers have mixed/customized alert modes.
  bool get hasMixedModes =>
      !allPrayersAreAlarm && !allPrayersAreNotification && !allPrayersAreOff;

  /// Returns the unified global mode if all prayers share the same mode, otherwise null.
  PrayerAlarmType? get dominantGlobalMode {
    if (allPrayersAreAlarm) return PrayerAlarmType.alarm;
    if (allPrayersAreNotification) return PrayerAlarmType.notification;
    if (allPrayersAreOff) return PrayerAlarmType.off;
    return null;
  }

  /// Whether any of the 5 prayers is currently undergoing a mode transition.
  bool get isAnyPrayerTransitioning =>
      isUpdatingAllPrayers || PrayerId.values.any((id) => isTransitioning(id));

  /// Whether a transition is actively pending or waiting for an imminent alarm.
  bool isTransitioning(PrayerId prayerId) {
    final transition = activeTransitions[prayerId];
    return transition != null &&
        (transition.status == TransitionStatus.pending ||
            transition.status == TransitionStatus.reconciling ||
            transition.status == TransitionStatus.waitingForImminentAlarm);
  }

  /// Whether the transition is currently in the imminent deferred window.
  bool isImminentDeferred(PrayerId prayerId) {
    final transition = activeTransitions[prayerId];
    return transition != null &&
        transition.status == TransitionStatus.waitingForImminentAlarm;
  }

  PrayerAlarmSettingsState copyWith({
    SettingsStatus? status,
    Map<PrayerId, PrayerAlarmConfig>? configs,
    Map<PrayerId, PrayerAlertTransitionRecord>? activeTransitions,
    double? globalAdhanVolume,
    bool? isGlobalAdhanVibrationEnabled,
    AudioSourceConfig? globalAudioSource,
    AudioSourceConfig? playingPreviewSource,
    bool clearPreview = false,
    bool? isPreviewPlaying,
    bool? isUpdatingAllPrayers,
    String? errorMessage,
    bool clearError = false,
    String? infoMessage,
    bool clearInfo = false,
  }) {
    return PrayerAlarmSettingsState(
      status: status ?? this.status,
      configs: configs ?? this.configs,
      activeTransitions: activeTransitions ?? this.activeTransitions,
      globalAdhanVolume: globalAdhanVolume ?? this.globalAdhanVolume,
      isGlobalAdhanVibrationEnabled:
          isGlobalAdhanVibrationEnabled ?? this.isGlobalAdhanVibrationEnabled,
      globalAudioSource: globalAudioSource ?? this.globalAudioSource,
      playingPreviewSource: clearPreview
          ? null
          : (playingPreviewSource ?? this.playingPreviewSource),
      isPreviewPlaying: isPreviewPlaying ?? this.isPreviewPlaying,
      isUpdatingAllPrayers: isUpdatingAllPrayers ?? this.isUpdatingAllPrayers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        configs,
        activeTransitions,
        globalAdhanVolume,
        isGlobalAdhanVibrationEnabled,
        globalAudioSource,
        playingPreviewSource,
        isPreviewPlaying,
        isUpdatingAllPrayers,
        errorMessage,
        infoMessage,
      ];
}

