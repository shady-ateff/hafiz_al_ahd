import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';

class FakeConfigRepository implements BasePrayerAlarmConfigRepository {
  final Map<PrayerId, PrayerAlarmConfig> configs = {};

  FakeConfigRepository() {
    for (final id in PrayerId.values) {
      configs[id] = PrayerAlarmConfig(prayerId: id, alarmType: PrayerAlarmType.alarm);
    }
  }

  @override
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId) async => configs[prayerId]!;

  @override
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs() async => Map.from(configs);

  @override
  Future<void> saveConfig(PrayerAlarmConfig config) async {
    configs[config.prayerId] = config;
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> newConfigs) async {
    configs.addAll(newConfigs);
  }

  @override
  Future<bool> migrateLegacyConfigsIfNeeded() async => false;

  @override
  Future<int> getMigrationVersion() async => 2;
}

class FakeAudioPlayer extends AudioPlayer {
  bool isPlaying = false;
  Source? currentSource;

  @override
  Future<void> play(Source source, {double? volume, double? balance, AudioContext? ctx, Duration? position, PlayerMode? mode}) async {
    isPlaying = true;
    currentSource = source;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    isPlaying = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakeConfigRepository configRepo;
  late PrayerAlertTransitionLocalDataSourceImpl transitionDataSource;
  late TransitionCoordinator coordinator;
  late FakeAudioPlayer audioPlayer;
  late PrayerAlarmSettingsCubit cubit;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    configRepo = FakeConfigRepository();
    transitionDataSource = PrayerAlertTransitionLocalDataSourceImpl(prefs: prefs);
    audioPlayer = FakeAudioPlayer();

    coordinator = TransitionCoordinator(
      configRepository: configRepo,
      transitionDataSource: transitionDataSource,
      cancelAlarmSafely: (id, {expectedScheduledTime, expectedAssetAudioPath}) async =>
          EventCancellationStatus.cancelled,
      stopActiveAlarm: (id) async {},
      cancelNotificationSafely: (id) async => EventCancellationStatus.cancelled,
      scheduleAlarm: (id, dt, audio, vol, vib) async {},
      scheduleNotification: (id, dt) async {},
      getPrayerTimesForHorizon: (id) async => [DateTime(2026, 11, 10, 15, 30)],
    );

    cubit = PrayerAlarmSettingsCubit(
      configRepository: configRepo,
      transitionCoordinator: coordinator,
      transitionDataSource: transitionDataSource,
      prefs: prefs,
      audioStorageLock: AudioStorageLock(),
      storageService: CustomAudioStorageService(),
      audioPlayer: audioPlayer,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  group('P4.1-C.3 — PrayerAlarmSettingsCubit State Isolation & Audio Lifecycle', () {
    test('Initial load populates configurations for all 5 prayers', () async {
      await cubit.loadSettings();
      expect(cubit.state.status, equals(SettingsStatus.loaded));
      expect(cubit.state.configs.length, equals(5));
      expect(cubit.state.globalAdhanVolume, equals(1.0));
      expect(cubit.state.isGlobalAdhanVibrationEnabled, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST-C-20: Per-Prayer State Isolation
    // -------------------------------------------------------------------------
    test('TEST-C-20: Toggling Asr updates Asr mode exclusively (sibling prayers untouched)', () async {
      await cubit.loadSettings();

      // Toggle Asr from Alarm -> Notification
      await cubit.toggleAlertMode(PrayerId.asr);

      expect(cubit.state.getEffectiveMode(PrayerId.asr), equals(PrayerAlarmType.notification));

      // Sibling prayers remain Alarm
      expect(cubit.state.getEffectiveMode(PrayerId.fajr), equals(PrayerAlarmType.alarm));
      expect(cubit.state.getEffectiveMode(PrayerId.dhuhr), equals(PrayerAlarmType.alarm));
      expect(cubit.state.getEffectiveMode(PrayerId.maghrib), equals(PrayerAlarmType.alarm));
      expect(cubit.state.getEffectiveMode(PrayerId.isha), equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // TEST-C-21: Audio Preview Lifecycle
    // -------------------------------------------------------------------------
    test('TEST-C-21: Audio preview play and stop cycles correctly update state', () async {
      const audioSource = BuiltInAudioSource(
        id: 'builtIn:custom',
        displayName: 'مؤذن الحرم',
        assetPath: 'assets/sounds/makkah.mp3',
      );

      await cubit.playAudioPreview(audioSource);
      expect(cubit.state.isPreviewPlaying, isTrue);
      expect(cubit.state.playingPreviewSource, equals(audioSource));
      expect(audioPlayer.isPlaying, isTrue);

      await cubit.stopAudioPreview();
      expect(cubit.state.isPreviewPlaying, isFalse);
      expect(cubit.state.playingPreviewSource, isNull);
      expect(audioPlayer.isPlaying, isFalse);
    });

    test('Off mode tapping produces informational guidance without changing mode', () async {
      await configRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.off),
      );
      await cubit.loadSettings();

      await cubit.toggleAlertMode(PrayerId.maghrib);

      // Mode remains off
      expect(cubit.state.getEffectiveMode(PrayerId.maghrib), equals(PrayerAlarmType.off));
      expect(cubit.state.infoMessage, contains('التنبيه معطل لهذه الصلاة'));
    });

    test('Volume clamping and vibration override updates', () async {
      await cubit.loadSettings();

      await cubit.updatePrayerVolume(PrayerId.fajr, 0.45);
      expect(cubit.state.configs[PrayerId.fajr]!.volume, equals(0.45));

      await cubit.updatePrayerVibration(PrayerId.fajr, false);
      expect(cubit.state.configs[PrayerId.fajr]!.isVibrationEnabled, isFalse);

      await cubit.updatePrayerVibration(PrayerId.fajr, null);
      expect(cubit.state.configs[PrayerId.fajr]!.isVibrationEnabled, isNull);
    });

    group('Phase P4.1-C.10 — Unified Global Adhan Settings & Inheritance Matrix', () {
      test('updateGlobalVolume clamps and persists to SharedPreferences', () async {
        await cubit.loadSettings();

        await cubit.updateGlobalVolume(0.75);
        expect(cubit.state.globalAdhanVolume, equals(0.75));
        expect(prefs.getDouble('adhan_volume'), equals(0.75));

        // Clamping upper bound
        await cubit.updateGlobalVolume(1.5);
        expect(cubit.state.globalAdhanVolume, equals(1.0));
        expect(prefs.getDouble('adhan_volume'), equals(1.0));

        // Clamping lower bound
        await cubit.updateGlobalVolume(0.01);
        expect(cubit.state.globalAdhanVolume, equals(0.1));
        expect(prefs.getDouble('adhan_volume'), equals(0.1));
      });

      test('updateGlobalVibration updates state and persists to SharedPreferences', () async {
        await cubit.loadSettings();
        expect(cubit.state.isGlobalAdhanVibrationEnabled, isTrue);

        await cubit.updateGlobalVibration(false);
        expect(cubit.state.isGlobalAdhanVibrationEnabled, isFalse);
        expect(prefs.getBool('isAdhanVibrationEnabled'), isFalse);

        await cubit.updateGlobalVibration(true);
        expect(cubit.state.isGlobalAdhanVibrationEnabled, isTrue);
        expect(prefs.getBool('isAdhanVibrationEnabled'), isTrue);
      });

      test('updateGlobalAudioSource updates state and persists JSON to SharedPreferences', () async {
        await cubit.loadSettings();
        const customBuiltIn = BuiltInAudioSource(
          id: 'builtIn:custom_global',
          displayName: 'الأذان المدني',
          assetPath: 'assets/sounds/madinah.mp3',
        );

        await cubit.updateGlobalAudioSource(customBuiltIn);
        expect(cubit.state.globalAudioSource, equals(customBuiltIn));
        final storedJson = prefs.getString('global_adhan_audio_source');
        expect(storedJson, isNotNull);
        expect(storedJson, contains('الأذان المدني'));
      });

      test('Inheritance Matrix: Volume override vs Global fallback', () async {
        await cubit.loadSettings();
        await cubit.updateGlobalVolume(0.8);

        // Prayer without override inherits global volume
        expect(cubit.state.getEffectiveVolume(PrayerId.dhuhr), equals(0.8));

        // Prayer with explicit override maintains override
        await cubit.updatePrayerVolume(PrayerId.asr, 0.4);
        expect(cubit.state.getEffectiveVolume(PrayerId.asr), equals(0.4));

        // Changing global volume affects un-overridden prayer, but not overridden prayer
        await cubit.updateGlobalVolume(0.6);
        expect(cubit.state.getEffectiveVolume(PrayerId.dhuhr), equals(0.6));
        expect(cubit.state.getEffectiveVolume(PrayerId.asr), equals(0.4));

        // Clearing volume override resets prayer to inherit global volume
        await cubit.updatePrayerVolume(PrayerId.asr, null, clearOverride: true);
        expect(cubit.state.getEffectiveVolume(PrayerId.asr), equals(0.6));
      });

      test('Inheritance Matrix: Vibration override vs Global fallback', () async {
        await cubit.loadSettings();
        await cubit.updateGlobalVibration(true);

        // Inheriting
        expect(cubit.state.getEffectiveVibration(PrayerId.maghrib), isTrue);

        // Overriding
        await cubit.updatePrayerVibration(PrayerId.maghrib, false);
        expect(cubit.state.getEffectiveVibration(PrayerId.maghrib), isFalse);

        // Changing global does not affect overridden prayer
        await cubit.updateGlobalVibration(false);
        expect(cubit.state.getEffectiveVibration(PrayerId.dhuhr), isFalse);
        expect(cubit.state.getEffectiveVibration(PrayerId.maghrib), isFalse);

        // Clearing override returns to global inheritance
        await cubit.updatePrayerVibration(PrayerId.maghrib, null);
        await cubit.updateGlobalVibration(true);
        expect(cubit.state.getEffectiveVibration(PrayerId.maghrib), isTrue);
      });

      test('Inheritance Matrix: Audio source override vs Global fallback', () async {
        await cubit.loadSettings();
        const customGlobal = BuiltInAudioSource(
          id: 'builtIn:custom_global',
          displayName: 'الأذان المدني',
          assetPath: 'assets/sounds/madinah.mp3',
          fajrAssetPath: 'assets/sounds/madinah_fajr.mp3',
        );
        await cubit.updateGlobalAudioSource(customGlobal);

        // Prayers without override inherit global audio source
        expect(cubit.state.getEffectiveAudioSource(PrayerId.dhuhr), equals(customGlobal));
        expect(cubit.state.getEffectiveAudioSource(PrayerId.asr), equals(customGlobal));
        expect(cubit.state.getEffectiveAudioSource(PrayerId.fajr), equals(customGlobal));
        expect(
          (cubit.state.getEffectiveAudioSource(PrayerId.fajr) as BuiltInAudioSource)
              .resolveAssetPath(isFajr: true),
          equals('assets/sounds/madinah_fajr.mp3'),
        );

        // Custom override on a prayer takes precedence
        const specialAudio = BuiltInAudioSource(
          id: 'builtIn:special',
          displayName: 'أذان خاص',
          assetPath: 'assets/sounds/special.mp3',
        );
        await cubit.updatePrayerAudioSource(PrayerId.dhuhr, specialAudio);
        expect(cubit.state.getEffectiveAudioSource(PrayerId.dhuhr), equals(specialAudio));

        // Clearing override returns Dhuhr to inheriting customGlobal
        await cubit.updatePrayerAudioSource(PrayerId.dhuhr, null, clearOverride: true);
        expect(cubit.state.getEffectiveAudioSource(PrayerId.dhuhr), equals(customGlobal));
      });

      test('setAllPrayersMode transitions all 5 prayers simultaneously', () async {
        await cubit.loadSettings();

        // Initially all are alarm
        expect(cubit.state.allPrayersAreAlarm, isTrue);

        // Transition all to notification
        await cubit.setAllPrayersMode(PrayerAlarmType.notification);
        expect(cubit.state.allPrayersAreNotification, isTrue);
        for (final id in PrayerId.values) {
          expect(cubit.state.getEffectiveMode(id), equals(PrayerAlarmType.notification));
        }

        // Transition all back to alarm
        await cubit.setAllPrayersMode(PrayerAlarmType.alarm);
        expect(cubit.state.allPrayersAreAlarm, isTrue);
        for (final id in PrayerId.values) {
          expect(cubit.state.getEffectiveMode(id), equals(PrayerAlarmType.alarm));
        }
      });
    });
  });
}

