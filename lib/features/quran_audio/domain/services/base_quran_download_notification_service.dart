/// Pure contract for OS-level download notifications.
///
/// Follows C1, C5, C6 architecture:
/// - Dedicated silent channel with low importance.
/// - Scoped dismissal methods preventing accidental cancellation of other app notifications.
/// - Android supports progress bars and ongoing notifications; iOS gracefully handles lifecycle alerts.
abstract class BaseQuranDownloadNotificationService {
  /// Deterministic notification ID for single-Surah download.
  static const int kSingleSurahDownloadNotificationId = 9100;

  /// Deterministic notification ID for full-Quran library queue download.
  static const int kFullQuranDownloadNotificationId = 9200;

  /// Notification channel configuration.
  static const String kDownloadNotificationChannelId = 'quran_audio_download_channel_v2';
  static const String kDownloadNotificationChannelName = 'تحميل القرآن الكريم';
  static const String kDownloadNotificationChannelDescription =
      'إشعارات متابعة تحميل التلاوات القرآنية والمصحف الشريف';

  /// Initializes notification channel and platform settings.
  Future<void> initialize();

  /// Displays or updates an active progress notification (with progress bar on Android).
  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required double? progressRatio,
    required bool isOngoing,
    required bool isIndeterminate,
  });

  /// Displays a terminal notification (completion or failure).
  Future<void> showTerminalNotification({
    required int id,
    required String title,
    required String body,
    required bool isError,
  });

  /// Cancels a specific notification by its ID.
  Future<void> dismissNotification(int id);

  /// Dismisses only the single-Surah download notification.
  Future<void> dismissSingleSurahNotification();

  /// Dismisses only the full-Quran queue download notification.
  Future<void> dismissQueueNotification();

  /// Dismisses ALL download notifications belonging exclusively to this subsystem.
  ///
  /// CRITICAL (C5): MUST NOT call `cancelAll()` on the plugin to protect Adhan and Azkar alarms.
  Future<void> dismissAllQuranDownloadNotifications();
}
