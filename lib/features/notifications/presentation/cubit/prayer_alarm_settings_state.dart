import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alert_transition_record.dart';

enum SettingsStatus { initial, loading, loaded, error }

class PrayerAlarmSettingsState extends Equatable {
  static const AudioSourceConfig defaultGeneralAudio = BuiltInAudioSource(
    id: 'builtIn:default_general',
    displayName: 'الأذان العام (الافتراضي)',
    assetPath: 'assets/sounds/adhan.mp3',
  );

  final SettingsStatus status;
  final Map<PrayerId, PrayerAlarmConfig> configs;
  final Map<PrayerId, PrayerAlertTransitionRecord> activeTransitions;
  final double globalAdhanVolume;
  final bool isGlobalAdhanVibrationEnabled;
  final AudioSourceConfig globalAudioSource;
  final AudioSourceConfig? playingPreviewSource;
  final bool isPreviewPlaying;
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
    if (prayerId == PrayerId.fajr) {
      return AudioSourceConfig.defaultBuiltInFallback(isFajr: true);
    }
    return globalAudioSource;
  }

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
        errorMessage,
        infoMessage,
      ];
}

