import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/prayer_alarm_settings_screen.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/prayer_detail_settings_screen.dart';

class MockConfigRepo implements BasePrayerAlarmConfigRepository {
  final Map<PrayerId, PrayerAlarmConfig> configs;

  MockConfigRepo(this.configs);

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
  late PrayerAlertTransitionLocalDataSourceImpl transitionDataSource;
  late TransitionCoordinator coordinator;
  late MockConfigRepo configRepo;
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

    SharedPreferences.setMockInitialValues({
      'adhan_volume': 0.8,
      'isAdhanVibrationEnabled': true,
    });
    prefs = await SharedPreferences.getInstance();
    transitionDataSource = PrayerAlertTransitionLocalDataSourceImpl(prefs: prefs);

    final Map<PrayerId, PrayerAlarmConfig> initialConfigs = {
      for (final id in PrayerId.values)
        id: PrayerAlarmConfig(
          prayerId: id,
          alarmType: PrayerAlarmType.alarm,
        ),
    };
    configRepo = MockConfigRepo(initialConfigs);

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

    audioPlayer = FakeAudioPlayer();

    cubit = PrayerAlarmSettingsCubit(
      configRepository: configRepo,
      transitionCoordinator: coordinator,
      transitionDataSource: transitionDataSource,
      prefs: prefs,
      audioPlayer: audioPlayer,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  Widget buildTestApp({Widget? home}) {
    return BlocProvider<PrayerAlarmSettingsCubit>.value(
      value: cubit,
      child: MaterialApp(
        home: home ?? const PrayerAlarmSettingsScreen(),
      ),
    );
  }

  group('P4.1-C.10 — PrayerAlarmSettingsScreen Widget Tests', () {
    testWidgets('Renders Section A, Section B, and Section C correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await cubit.loadSettings();

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Section A: Global defaults
      expect(find.text('الإعدادات العامة التلقائية'), findsOneWidget);
      expect(find.text('المؤذن الافتراضي العام'), findsOneWidget);
      expect(find.text('مستوى صوت الأذان الافتراضي'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget); // Initial volume 0.8
      expect(find.text('الاهتزاز الافتراضي مع الأذان'), findsOneWidget);

      // Section B: 5 Prayers
      expect(find.text('التحكم المستقل لكل صلاة'), findsOneWidget);
      expect(find.text('صلاة الفجر'), findsOneWidget);
      expect(find.text('صلاة الظهر'), findsOneWidget);
      expect(find.text('صلاة العصر'), findsOneWidget);
      expect(find.text('صلاة المغرب'), findsOneWidget);
      expect(find.text('صلاة العشاء'), findsOneWidget);

      // Section C: Catalog entry
      expect(find.text('مكتبة أصوات المؤذنين'), findsOneWidget);
      expect(find.text('تصفح وإدارة أصوات الأذان'), findsOneWidget);
    });

    testWidgets('Tapping global vibration switch toggles global vibration', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await cubit.loadSettings();
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      // Tap the vibration switch
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(cubit.state.isGlobalAdhanVibrationEnabled, isFalse);
      expect(prefs.getBool('isAdhanVibrationEnabled'), isFalse);
    });

    testWidgets('Tapping prayer card navigates to PrayerDetailSettingsScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await cubit.loadSettings();
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap on Fajr card
      await tester.tap(find.text('صلاة الفجر'));
      await tester.pumpAndSettle();

      // Verify navigated to detail screen
      expect(find.byType(PrayerDetailSettingsScreen), findsOneWidget);
      expect(find.text('تنبيه صلاة الفجر'), findsOneWidget);
      expect(find.text('طريقة التنبيه'), findsOneWidget);
      expect(find.text('منبه بكامل الشاشة'), findsOneWidget);
      expect(find.text('إشعار بسيط'), findsOneWidget);
      expect(find.text('إيقاف التنبيه'), findsOneWidget);
    });
  });
}

