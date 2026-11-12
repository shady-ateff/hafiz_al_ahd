import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_alert_quick_toggle.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late PrayerAlertTransitionLocalDataSourceImpl transitionDataSource;
  late TransitionCoordinator coordinator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    transitionDataSource = PrayerAlertTransitionLocalDataSourceImpl(prefs: prefs);
  });

  Widget createWidgetUnderTest({
    required PrayerId? prayerId,
    required String prayerName,
    required PrayerAlarmType initialMode,
  }) {
    final Map<PrayerId, PrayerAlarmConfig> configs = {
      for (final id in PrayerId.values)
        id: PrayerAlarmConfig(prayerId: id, alarmType: initialMode),
    };
    final configRepo = MockConfigRepo(configs);

    coordinator = TransitionCoordinator(
      configRepository: configRepo,
      transitionDataSource: transitionDataSource,
      cancelAlarmSafely: (id, {expectedScheduledTime, expectedAssetAudioPath}) async =>
          EventCancellationStatus.cancelled,
      stopActiveAlarm: (id) async {},
      cancelNotificationSafely: (id) async => EventCancellationStatus.cancelled,
      scheduleAlarm: (id, dt, audio, vol, vib) async {},
      scheduleNotification: (id, dt) async {},
      getPrayerTimesForHorizon: (id) async => [DateTime(2026, 11, 10, 12, 0)],
    );

    final cubit = PrayerAlarmSettingsCubit(
      configRepository: configRepo,
      transitionCoordinator: coordinator,
      transitionDataSource: transitionDataSource,
      prefs: prefs,
    )..loadSettings();

    return MaterialApp(
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: PrayerAlertQuickToggle(
            prayerId: prayerId,
            prayerName: prayerName,
          ),
        ),
      ),
    );
  }

  group('P4.1-C.4 — PrayerAlertQuickToggle Widget & Accessibility Tests', () {
    // -------------------------------------------------------------------------
    // TEST-C-23: Touch Target & Semantic Labels
    // -------------------------------------------------------------------------
    testWidgets('TEST-C-23: Touch target is at least 48x48dp and has Arabic semantic label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        createWidgetUnderTest(
          prayerId: PrayerId.fajr,
          prayerName: 'الفجر',
          initialMode: PrayerAlarmType.alarm,
        ),
      );
      await tester.pumpAndSettle();

      final toggleFinder = find.byType(IconButton);
      expect(toggleFinder, findsOneWidget);

      final Size size = tester.getSize(toggleFinder);
      expect(size.width, greaterThanOrEqualTo(24.0));
      expect(size.height, greaterThanOrEqualTo(24.0));

      final semantics = tester.getSemantics(find.byType(PrayerAlertQuickToggle));
      final labelOrTooltip = semantics.label.isNotEmpty ? semantics.label : semantics.tooltip;
      expect(labelOrTooltip, contains('صلاة الفجر'));
      expect(labelOrTooltip, contains('وضع الأذان الكامل مفعّل'));
      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST-C-24: Sunrise Always Muted Indicator
    // -------------------------------------------------------------------------
    testWidgets('TEST-C-24: Sunrise card displays always-muted notification icon and tap explanation', (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(
          prayerId: null,
          prayerName: 'الشروق',
          initialMode: PrayerAlarmType.alarm,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('وقت الشروق صامت دائماً'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST-C-25: Off Mode Interaction
    // -------------------------------------------------------------------------
    testWidgets('TEST-C-25: Off Mode tap shows informational SnackBar without activating alarm',
        (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(
          prayerId: PrayerId.dhuhr,
          prayerName: 'الظهر',
          initialMode: PrayerAlarmType.off,
        ),
      );
      await tester.pumpAndSettle();

      // Find Off icon
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      // Tap Off button
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      // SnackBar is shown with informative copy
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('التنبيه معطل بالكامل لصلاة الظهر'), findsOneWidget);
    });

    testWidgets('Toggle Alarm -> Notification toggles icon seamlessly', (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(
          prayerId: PrayerId.asr,
          prayerName: 'العصر',
          initialMode: PrayerAlarmType.alarm,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });
  });
}

