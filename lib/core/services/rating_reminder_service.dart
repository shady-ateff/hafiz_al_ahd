import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/widgets/app_rating_dialog.dart';

/// Service responsible for managing app rating reminders on Google Play Store.
///
/// Follows polite prompting rules:
/// - Increments launch count on app startup.
/// - Prompts user only after a minimal usage threshold (e.g., 3 launches).
/// - Respects "Rate Now" (never prompts again).
/// - Respects "Don't Ask Again" (never prompts again).
/// - Delays re-prompting by at least 3 days if the user chooses "Remind Me Later".
class RatingReminderService {
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.shadyatef.hafiz_alahd&pcampaignid=web_share';

  static const String keyHasRated = 'rating_has_rated';
  static const String keyNeverRemind = 'rating_never_remind';
  static const String keyLaunchCount = 'rating_launch_count';
  static const String keyLastRemindTime = 'rating_last_remind_time';

  /// Minimum launches before showing automated reminder
  static const int minLaunchCount = 3;

  /// Minimum duration between "Remind Me Later" and next prompt (3 days)
  static const Duration remindLaterDelay = Duration(days: 3);

  /// Helper to get SharedPreferences instance
  static SharedPreferences get _prefs {
    if (sl.isRegistered<SharedPreferences>()) {
      return sl<SharedPreferences>();
    }
    throw StateError('SharedPreferences not registered in service locator');
  }

  /// Increments launch count and checks if the rating dialog should be displayed.
  ///
  /// This should be invoked on app startup after the initial frame renders.
  static Future<void> checkAndShowPrompt(
    BuildContext context, {
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    try {
      final prefs = _prefs;

      final bool hasRated = prefs.getBool(keyHasRated) ?? false;
      if (hasRated) return;

      final bool neverRemind = prefs.getBool(keyNeverRemind) ?? false;
      if (neverRemind) return;

      final int currentLaunches = (prefs.getInt(keyLaunchCount) ?? 0) + 1;
      await prefs.setInt(keyLaunchCount, currentLaunches);

      if (currentLaunches < minLaunchCount) {
        return;
      }

      final int? lastRemindMs = prefs.getInt(keyLastRemindTime);
      if (lastRemindMs != null) {
        final lastRemindDate = DateTime.fromMillisecondsSinceEpoch(lastRemindMs);
        final elapsed = DateTime.now().difference(lastRemindDate);
        if (elapsed < remindLaterDelay) {
          return;
        }
      }

      // Polite delay so dialog does not block immediate startup interactions
      await Future.delayed(initialDelay);

      if (!context.mounted) return;

      showRatingDialog(context);
    } catch (e) {
      debugPrint('RatingReminderService.checkAndShowPrompt error: $e');
    }
  }

  /// Displays the rating reminder dialog.
  static Future<void> showRatingDialog(BuildContext context) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AppRatingDialog(
        onRateNow: () => rateNow(dialogContext),
        onRemindLater: () => remindLater(dialogContext),
        onNeverAskAgain: () => neverAskAgain(dialogContext),
      ),
    );
  }

  /// Handles "Rate Now" action: launches Play Store URL and marks as rated.
  static Future<void> rateNow(BuildContext context) async {
    try {
      final prefs = _prefs;
      await prefs.setBool(keyHasRated, true);

      final Uri uri = Uri.parse(playStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('RatingReminderService.rateNow error: $e');
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// Handles "Remind Me Later" action: stamps last reminder time.
  static Future<void> remindLater(BuildContext context) async {
    try {
      final prefs = _prefs;
      await prefs.setInt(
        keyLastRemindTime,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('RatingReminderService.remindLater error: $e');
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// Handles "Don't Ask Again" action: suppresses future automated prompts.
  static Future<void> neverAskAgain(BuildContext context) async {
    try {
      final prefs = _prefs;
      await prefs.setBool(keyNeverRemind, true);
    } catch (e) {
      debugPrint('RatingReminderService.neverAskAgain error: $e');
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }
}

