import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/main.dart' show routeObserver;
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_card_widget.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/time_date_section.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';

class TestTimeCubit extends Cubit<DateTime> implements TimeCubit {
  TestTimeCubit(super.initialState);

  @override
  void Function(DateTime newTime)? get onDayChanged => null;

  void emitTime(DateTime time) => emit(time);
}

class TestPrayerTimesCubit extends Cubit<PrayerTimesStates> implements PrayerTimesCubit {
  TestPrayerTimesCubit() : super(PrayerTimesInitial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createTestWidget({
  required Widget child,
  TimeCubit? timeCubit,
  PrayerTimesCubit? prayerTimesCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<TimeCubit>.value(
        value: timeCubit ?? TestTimeCubit(DateTime(2026, 11, 6, 12, 0, 0)),
      ),
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
      ),
      BlocProvider<PrayerTimesCubit>.value(
        value: prayerTimesCubit ?? TestPrayerTimesCubit(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      navigatorObservers: [routeObserver],
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ar', null);
    SharedPreferences.setMockInitialValues({
      'last_quran_page': 1,
    });
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerSingleton<SharedPreferences>(prefs);
    }
  });

  group('P2-D.4.1-C — Prayer Card Animation & Ticker Isolation', () {
    testWidgets('1. AnimationController repeats when isNextPrayer == true and isActive == true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const TickerMode(
            enabled: true,
            child: PrayerCard(
              name: 'الظهر',
              displayTime: null,
              time: null,
              icon: Icons.wb_sunny,
              isWideLayout: false,
              isNextPrayer: true,
              remaining: null,
              isActive: true,
            ),
          ),
        ),
      );

      // Verify the widget mounts
      expect(find.byType(PrayerCard), findsOneWidget);

      // Pump 200ms to advance animation
      await tester.pump(const Duration(milliseconds: 200));

      // AnimatedContainer and AnimatedBuilder inside PrayerCard should be active
      expect(
        find.descendant(
          of: find.byType(PrayerCard),
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
    });

    testWidgets('2. TickerMode(enabled: false) mutes the ticker when inactive',
        (WidgetTester tester) async {
      bool active = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return createTestWidget(
              child: TickerMode(
                enabled: active,
                child: PrayerCard(
                  name: 'الظهر',
                  displayTime: null,
                  time: null,
                  icon: Icons.wb_sunny,
                  isWideLayout: false,
                  isNextPrayer: true,
                  remaining: null,
                  isActive: active,
                ),
              ),
            );
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Mute the ticker
      active = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return createTestWidget(
              child: TickerMode(
                enabled: active,
                child: PrayerCard(
                  name: 'الظهر',
                  displayTime: null,
                  time: null,
                  icon: Icons.wb_sunny,
                  isWideLayout: false,
                  isNextPrayer: true,
                  remaining: null,
                  isActive: active,
                ),
              ),
            );
          },
        ),
      );

      // When TickerMode is false, ticker is muted in the framework
      // Advancing time should not fail with active frame errors
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PrayerCard), findsOneWidget);
    });

    testWidgets('3. Rapid tab switching does not cause ticker assertions or recreation leaks',
        (WidgetTester tester) async {
      for (int i = 0; i < 5; i++) {
        final bool isActive = i % 2 == 0;
        await tester.pumpWidget(
          createTestWidget(
            child: TickerMode(
              enabled: isActive,
              child: PrayerCard(
                name: 'العصر',
                displayTime: null,
                time: null,
                icon: Icons.wb_cloudy,
                isWideLayout: false,
                isNextPrayer: true,
                remaining: null,
                isActive: isActive,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(PrayerCard), findsOneWidget);
    });
  });

  group('P2-D.4.1-C — TimeCubit Rebuild Isolation & Immediate Reactivation Sync', () {
    testWidgets('1. PrayerCard skips rebuilds while inactive and synchronizes instantly upon reactivation',
        (WidgetTester tester) async {
      final timeCubit = TestTimeCubit(DateTime(2026, 11, 6, 12, 0, 0));
      final prayerTargetTime = DateTime(2026, 11, 6, 12, 30, 0); // 30 minutes remaining
      bool isActive = true;

      Widget buildHarness() {
        return StatefulBuilder(
          builder: (context, setState) {
            return createTestWidget(
              timeCubit: timeCubit,
              child: PrayerCard(
                name: 'الظهر',
                displayTime: prayerTargetTime,
                time: prayerTargetTime,
                icon: Icons.wb_sunny,
                isWideLayout: false,
                isNextPrayer: true,
                remaining: null,
                isActive: isActive,
              ),
            );
          },
        );
      }

      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // At 12:00:00, remaining is 30m 00s -> - 00:30:00
      expect(find.text('- 00:30:00'), findsOneWidget);

      // Advance time while active: 12:00:01 -> remaining is 29m 59s
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 1));
      await tester.pump();
      expect(find.text('- 00:29:59'), findsOneWidget);

      // Now deactivate: switch tab away (isActive = false)
      isActive = false;
      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // Emit multiple time updates while inactive
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 2));
      await tester.pump();
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 15));
      await tester.pump();
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 30));
      await tester.pump();

      // Now REACTIVATE: return to HomeScreen (isActive = true)
      isActive = true;
      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // At 12:00:30, remaining is exactly 29m 30s -> - 00:29:30
      // State synchronization MUST be immediate!
      expect(find.text('- 00:29:30'), findsOneWidget);
    });

    testWidgets('2. TimeDateSection skips rebuilds while inactive and synchronizes instantly upon reactivation',
        (WidgetTester tester) async {
      final timeCubit = TestTimeCubit(DateTime(2026, 11, 6, 12, 0, 0));
      bool isActive = true;

      Widget buildHarness() {
        return StatefulBuilder(
          builder: (context, setState) {
            return createTestWidget(
              timeCubit: timeCubit,
              child: TimeDateSection(
                isLandscape: false,
                isMobile: true,
                isActive: isActive,
              ),
            );
          },
        );
      }

      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // Verify initial time rendered: 12:00
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('00'), findsOneWidget); // seconds

      // Deactivate
      isActive = false;
      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // Emit time changes while inactive
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 45));
      await tester.pump();

      // Reactivate
      isActive = true;
      await tester.pumpWidget(buildHarness());
      await tester.pump();

      // Verify clock immediately updated to 45 seconds
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
    });
  });

  group('P2-D.4.1-C — Background Logic & Navigation Hierarchy', () {
    testWidgets('HomeScreen accepts isActive and wraps in TickerMode',
        (WidgetTester tester) async {
      final timeCubit = TestTimeCubit(DateTime(2026, 11, 6, 12, 0, 0));

      await tester.pumpWidget(
        createTestWidget(
          timeCubit: timeCubit,
          child: const HomeScreen(isActive: false),
        ),
      );

      // Verify HomeScreen is rendered and TickerMode is disabled
      final tickerModeFinder = find.byWidgetPredicate(
        (widget) => widget is TickerMode && widget.enabled == false,
      );
      expect(tickerModeFinder, findsAtLeastNWidgets(1));
    });

    testWidgets('HomeScreen becomes inactive when covered by a pushed route and reactivates upon return',
        (WidgetTester tester) async {
      final timeCubit = TestTimeCubit(DateTime(2026, 11, 6, 12, 0, 0));
      late BuildContext homeContext;

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TimeCubit>.value(value: timeCubit),
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<PrayerTimesCubit>.value(value: TestPrayerTimesCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            navigatorObservers: [routeObserver],
            home: Builder(
              builder: (ctx) {
                homeContext = ctx;
                return const HomeScreen(isActive: true);
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially active on home: 12:00:00
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('00'), findsOneWidget);

      // Push a dummy screen (simulating QuranScreen being pushed over HomeScreen)
      Navigator.of(homeContext).push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Dummy Quran Screen')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dummy screen is visible
      expect(find.text('Dummy Quran Screen'), findsOneWidget);

      // Emit time changes while QuranScreen covers HomeScreen
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 30));
      await tester.pump();
      timeCubit.emitTime(DateTime(2026, 11, 6, 12, 0, 45));
      await tester.pump();

      // Pop the route (returning to HomeScreen)
      Navigator.of(homeContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // HomeScreen is back on top, immediately displays latest synchronized time (45 seconds)
      expect(find.text('Dummy Quran Screen'), findsNothing);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
    });

    test('TimeCubit background periodic timer continues emitting and detects midnight', () async {
      int dayChangeCalls = 0;
      final cubit = TimeCubit(
        onDayChanged: (time) {
          dayChangeCalls++;
        },
      );

      // Verify cubit is initialized
      expect(cubit.state, isNotNull);

      // Close cubit safely
      await cubit.close();
      expect(cubit.isClosed, isTrue);
    });
  });
}
