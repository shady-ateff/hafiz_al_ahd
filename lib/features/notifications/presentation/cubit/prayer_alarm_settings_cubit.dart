import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';

class PrayerAlarmSettingsCubit extends Cubit<PrayerAlarmSettingsState> {
  final BasePrayerAlarmConfigRepository configRepository;
  final TransitionCoordinator transitionCoordinator;
  final BasePrayerAlertTransitionLocalDataSource transitionDataSource;
  final SharedPreferences prefs;
  final BaseAudioStorageLock audioStorageLock;
  final CustomAudioStorageService storageService;
  final AudioPlayer _audioPlayer;
  StreamSubscription<void>? _playerCompleteSub;

  PrayerAlarmSettingsCubit({
    required this.configRepository,
    required this.transitionCoordinator,
    required this.transitionDataSource,
    required this.prefs,
    required this.audioStorageLock,
    required this.storageService,
    AudioPlayer? audioPlayer,
  })  : _audioPlayer = audioPlayer ?? AudioPlayer(),
        super(const PrayerAlarmSettingsState()) {
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      emit(state.copyWith(clearPreview: true, isPreviewPlaying: false));
    });
  }

  /// Loads configurations, active transitions, and global preferences.
  Future<void> loadSettings() async {
    emit(state.copyWith(status: SettingsStatus.loading));
    try {
      final configs = await configRepository.getConfigs();
      final activeTransitions = await transitionDataSource.getAllRecords();

      final globalVolume = prefs.getDouble('adhan_volume') ?? 1.0;
      final globalVibration = prefs.getBool('isAdhanVibrationEnabled') ?? true;

      AudioSourceConfig globalAudioSource = PrayerAlarmSettingsState.defaultGeneralAudio;
      final audioJson = prefs.getString('global_adhan_audio_source');
      if (audioJson != null) {
        try {
          final decoded = jsonDecode(audioJson) as Map<String, dynamic>;
          globalAudioSource = AudioSourceConfig.fromJson(decoded);
        } catch (_) {}
      }

      emit(state.copyWith(
        status: SettingsStatus.loaded,
        configs: configs,
        activeTransitions: activeTransitions,
        globalAdhanVolume: globalVolume,
        isGlobalAdhanVibrationEnabled: globalVibration,
        globalAudioSource: globalAudioSource,
      ));
    } catch (e) {
      log("❌ [PrayerAlarmSettingsCubit] Failed to load settings: $e");
      emit(state.copyWith(
        status: SettingsStatus.error,
        errorMessage: 'فشل تحميل إعدادات التنبيهات: $e',
      ));
    }
  }

  /// 1-Tap Quick Toggle from Home Prayer Card: Alarm <-> Notification.
  /// If Off, does not toggle directly; surfaces direct info prompt.
  Future<void> toggleAlertMode(
    PrayerId prayerId, {
    DateTime? scheduledEpoch,
    int? activeAlarmId,
    bool isRinging = false,
  }) async {
    final currentMode = state.getEffectiveMode(prayerId);

    if (currentMode == PrayerAlarmType.off) {
      emit(state.copyWith(
        infoMessage: 'التنبيه معطل لهذه الصلاة. يرجى تفعيله من الإعدادات التفصيلية.',
      ));
      return;
    }

    final targetMode = currentMode == PrayerAlarmType.alarm
        ? PrayerAlarmType.notification
        : PrayerAlarmType.alarm;

    await _executeModeTransition(
      prayerId: prayerId,
      targetMode: targetMode,
      scheduledEpoch: scheduledEpoch,
      activeAlarmId: activeAlarmId,
      isRinging: isRinging,
    );
  }

  /// Sets an explicit prayer alert mode (alarm, notification, off) from Settings.
  Future<void> setPrayerMode(PrayerId prayerId, PrayerAlarmType mode) async {
    await _executeModeTransition(
      prayerId: prayerId,
      targetMode: mode,
    );
  }

  /// Reschedules all future alarms with the updated settings immediately without app restart.
  Future<void> _reschedulePrayers() async {
    try {
      if (sl.isRegistered<GetCachedLocationUseCase>() &&
          sl.isRegistered<ScheduleWeeklyPrayersUseCase>()) {
        final locationResult = await sl<GetCachedLocationUseCase>()();
        await locationResult.fold(
          (failure) async => null,
          (location) async {
            final scheduler = sl<ScheduleWeeklyPrayersUseCase>();
            await scheduler.execute(
              location.latitude,
              location.longitude,
              location.city,
              location.country,
            );
          },
        );
      }
    } catch (e) {
      log('⚠️ [PrayerAlarmSettingsCubit] Auto-rescheduling failed: $e');
    }
  }

  /// Sets alert mode (alarm, notification, off) across all 5 prayers simultaneously.
  Future<void> setAllPrayersMode(PrayerAlarmType targetMode) async {
    emit(state.copyWith(isUpdatingAllPrayers: true));
    try {
      for (final id in PrayerId.values) {
        if (state.getEffectiveMode(id) != targetMode) {
          await _executeModeTransition(
            prayerId: id,
            targetMode: targetMode,
          );
        }
      }
      unawaited(_reschedulePrayers());
    } finally {
      emit(state.copyWith(isUpdatingAllPrayers: false));
    }
  }

  Future<void> _executeModeTransition({
    required PrayerId prayerId,
    required PrayerAlarmType targetMode,
    DateTime? scheduledEpoch,
    int? activeAlarmId,
    bool isRinging = false,
  }) async {
    // Immediately reflect optimistic/in-flight transition in UI
    final activeTransitions = Map<PrayerId, dynamic>.from(state.activeTransitions);
    emit(state.copyWith(activeTransitions: Map.from(activeTransitions)));

    final result = await transitionCoordinator.executeTransition(
      prayerId: prayerId,
      targetMode: targetMode,
      scheduledEpoch: scheduledEpoch,
      activeAlarmId: activeAlarmId,
      isRinging: isRinging,
    );

    if (result.isDeferred) {
      // Refresh transitions and configs
      final updatedTransitions = await transitionDataSource.getAllRecords();
      final updatedConfigs = await configRepository.getConfigs();

      emit(state.copyWith(
        configs: updatedConfigs,
        activeTransitions: updatedTransitions,
        infoMessage:
            'تعذر إلغاء منبه الصلاة الحالية لقرب موعده (< 15 ثانية). سيعمل المنبه الحالي مرة أخيرة، ثم تتحول الصلاة إلى وضع الإشعار البسيط.',
      ));
    } else if (result.isCompleted) {
      final updatedTransitions = await transitionDataSource.getAllRecords();
      final updatedConfigs = await configRepository.getConfigs();

      emit(state.copyWith(
        configs: updatedConfigs,
        activeTransitions: updatedTransitions,
        clearInfo: true,
        clearError: true,
      ));
    } else {
      final updatedTransitions = await transitionDataSource.getAllRecords();
      emit(state.copyWith(
        activeTransitions: updatedTransitions,
        errorMessage: result.errorMessage ?? 'فشل تحديث وضع التنبيه',
      ));
    }
  }

  /// Updates global default volume (propagates to all prayers without volume override).
  Future<void> updateGlobalVolume(double volume) async {
    final clamped = volume.clamp(0.1, 1.0).toDouble();
    await prefs.setDouble('adhan_volume', clamped);
    emit(state.copyWith(globalAdhanVolume: clamped));
    unawaited(_reschedulePrayers());
  }

  /// Updates global default vibration (propagates to all prayers without vibration override).
  Future<void> updateGlobalVibration(bool isEnabled) async {
    await prefs.setBool('isAdhanVibrationEnabled', isEnabled);
    emit(state.copyWith(isGlobalAdhanVibrationEnabled: isEnabled));
    unawaited(_reschedulePrayers());
  }

  /// Updates global default audio source (propagates to all non-Fajr prayers without audio override).
  Future<bool> updateGlobalAudioSource(AudioSourceConfig source) async {
    try {
      await audioStorageLock.synchronized(() async {
        if (source is CustomAudioSource) {
          await storageService.validatePathContainment(source.localRelativePath);
        }
        await prefs.setString('global_adhan_audio_source', jsonEncode(source.toJson()));
      });
      emit(state.copyWith(globalAudioSource: source, clearError: true));
      unawaited(_reschedulePrayers());
      return true;
    } on FileSystemException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'فشل حفظ الصوت العام: $e'));
      return false;
    }
  }

  /// Updates audio source for a specific prayer.
  Future<bool> updatePrayerAudioSource(
    PrayerId prayerId,
    AudioSourceConfig? audioSource, {
    bool clearOverride = false,
  }) async {
    final current = state.configs[prayerId];
    if (current == null) return false;

    try {
      final updated = clearOverride || audioSource == null
          ? current.copyWith(clearAudioOverride: true)
          : current.copyWith(audioSource: audioSource);
      await configRepository.saveConfig(updated);

      final updatedConfigs = Map<PrayerId, PrayerAlarmConfig>.from(state.configs);
      updatedConfigs[prayerId] = updated;
      emit(state.copyWith(configs: updatedConfigs, clearError: true));
      unawaited(_reschedulePrayers());
      return true;
    } on FileSystemException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'فشل حفظ إعداد الصوت: $e'));
      return false;
    }
  }

  /// Updates volume (clamped between 0.1 and 1.0) for a specific prayer.
  /// If [clearOverride] is true or [volume] is null, clears the override to inherit global volume.
  Future<void> updatePrayerVolume(
    PrayerId prayerId,
    double? volume, {
    bool clearOverride = false,
  }) async {
    final current = state.configs[prayerId];
    if (current == null) return;

    final updated = clearOverride || volume == null
        ? current.copyWith(clearVolumeOverride: true)
        : current.copyWith(volume: volume);
    await configRepository.saveConfig(updated);

    final updatedConfigs = Map<PrayerId, PrayerAlarmConfig>.from(state.configs);
    updatedConfigs[prayerId] = updated;
    emit(state.copyWith(configs: updatedConfigs));
    unawaited(_reschedulePrayers());
  }

  /// Updates vibration override for a specific prayer.
  /// Passing null clears the override, inheriting global vibration setting.
  Future<void> updatePrayerVibration(PrayerId prayerId, bool? isVibrationEnabled) async {
    final current = state.configs[prayerId];
    if (current == null) return;

    final updated = isVibrationEnabled == null
        ? current.copyWith(clearVibrationOverride: true)
        : current.copyWith(isVibrationEnabled: isVibrationEnabled);

    await configRepository.saveConfig(updated);

    final updatedConfigs = Map<PrayerId, PrayerAlarmConfig>.from(state.configs);
    updatedConfigs[prayerId] = updated;
    emit(state.copyWith(configs: updatedConfigs));
    unawaited(_reschedulePrayers());
  }

  /// Starts or toggles an audio preview without interfering with AlarmService.
  Future<void> playAudioPreview(AudioSourceConfig source, {bool isFajr = false}) async {
    try {
      if (state.isPreviewPlaying && state.playingPreviewSource?.id == source.id) {
        await stopAudioPreview();
        return;
      }

      await _audioPlayer.stop();

      emit(state.copyWith(
        playingPreviewSource: source,
        isPreviewPlaying: true,
      ));

      if (source is BuiltInAudioSource) {
        final rawPath = source.resolveAssetPath(isFajr: isFajr);
        final cleanPath = rawPath.startsWith('assets/') ? rawPath.substring(7) : rawPath;
        await _audioPlayer.play(AssetSource(cleanPath));
      } else if (source is CustomAudioSource) {
        await _audioPlayer.play(DeviceFileSource(source.localRelativePath));
      }
    } catch (e) {
      log("⚠️ [PrayerAlarmSettingsCubit] Audio preview failed: $e");
      emit(state.copyWith(clearPreview: true, isPreviewPlaying: false));
    }
  }

  /// Stops any actively running audio preview.
  Future<void> stopAudioPreview() async {
    await _audioPlayer.stop();
    emit(state.copyWith(clearPreview: true, isPreviewPlaying: false));
  }

  @override
  Future<void> close() async {
    await _playerCompleteSub?.cancel();
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    return super.close();
  }
}

