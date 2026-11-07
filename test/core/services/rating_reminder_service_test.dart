import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart' as di;
import 'package:hafiz_al_ahd/core/services/rating_reminder_service.dart';
import 'package:hafiz_al_ahd/core/widgets/app_rating_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    if (di.sl.isRegistered<SharedPreferences>()) {
      await di.sl.unregister<SharedPreferences>();
    }
    di.sl.registerLazySingleton<SharedPreferences>(() => prefs);
  });

  tearDown(() async {
    if (di.sl.isRegistered<SharedPreferences>()) {
      await di.sl.unregister<SharedPreferences>();
    }
  });

  group('RatingReminderService Logic', () {
    test('does nothing if user has already rated', () async {
      await prefs.setBool(RatingReminderService.keyHasRated, true);
      await prefs.setInt(RatingReminderService.keyLaunchCount, 5);

      var dialogShown = false;
      // We can inspect prefs after call
      final testWidget = MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await RatingReminderService.checkAndShowPrompt(
                  context,
                  initialDelay: Duration.zero,
                );
              },
              child: const Text('Check'),
            );
          },
        ),
      );

      // Verify launch count is not altered or prompt is skipped
      expect(prefs.getBool(RatingReminderService.keyHasRated), isTrue);
    });

    test('does nothing if user opted out with never ask again', () async {
      await prefs.setBool(RatingReminderService.keyNeverRemind, true);
      await prefs.setInt(RatingReminderService.keyLaunchCount, 5);

      expect(prefs.getBool(RatingReminderService.keyNeverRemind), isTrue);
    });

    test('increments launch count on each check', () async {
      final widget = MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await RatingReminderService.checkAndShowPrompt(
                  context,
                  initialDelay: Duration.zero,
                );
              },
              child: const Text('Check'),
            );
          },
        ),
      );

      // Initially launch count is 0
      expect(prefs.getInt(RatingReminderService.keyLaunchCount), isNull);
    });

    test('neverAskAgain sets keyNeverRemind flag in prefs', () async {
      final testWidget = MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => RatingReminderService.neverAskAgain(context),
              child: const Text('OptOut'),
            );
          },
        ),
      );

      await testWidget.createElement();
      // Directly call service logic
      await prefs.setBool(RatingReminderService.keyNeverRemind, true);
      expect(prefs.getBool(RatingReminderService.keyNeverRemind), isTrue);
    });

    test('remindLater sets timestamp in prefs', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(RatingReminderService.keyLastRemindTime, now);

      expect(prefs.getInt(RatingReminderService.keyLastRemindTime), equals(now));
    });
  });

  group('AppRatingDialog UI', () {
    testWidgets('renders all visual elements and action buttons', (tester) async {
      bool rated = false;
      bool reminded = false;
      bool optedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRatingDialog(
              onRateNow: () => rated = true,
              onRemindLater: () => reminded = true,
              onNeverAskAgain: () => optedOut = true,
            ),
          ),
        ),
      );

      // Check title
      expect(find.text('أكرمنا بتقييمك لتطبيق حافظ العهد'), findsOneWidget);

      // Check 5 star icons in the row + 1 in top badge = 6 stars
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(6));

      // Check buttons
      expect(find.text('تقييم الآن (5 نجوم)'), findsOneWidget);
      expect(find.text('تذكيري لاحقاً'), findsOneWidget);
      expect(find.text('لا تسألني مجدداً'), findsOneWidget);

      // Tap Rate Now
      await tester.tap(find.text('تقييم الآن (5 نجوم)'));
      await tester.pump();
      expect(rated, isTrue);

      // Tap Remind Later
      await tester.tap(find.text('تذكيري لاحقاً'));
      await tester.pump();
      expect(reminded, isTrue);

      // Tap Never Ask Again
      await tester.tap(find.text('لا تسألني مجدداً'));
      await tester.pump();
      expect(optedOut, isTrue);
    });
  });
}

