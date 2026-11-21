import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../domain/services/base_quran_download_notification_service.dart';

/// Concrete implementation of [BaseQuranDownloadNotificationService] backed by [FlutterLocalNotificationsPlugin].
///
/// Complies with:
/// - C1: Android-specific rich progress bars, ongoing notifications, and iOS platform degradation.
/// - C5: Scoped dismissals preserving other app notification domains.
/// - C6: Absolute silence via channel and notification configuration (`playSound: false`, `enableVibration: false`, `onlyAlertOnce: true`).
class QuranDownloadNotificationService implements BaseQuranDownloadNotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;

  QuranDownloadNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        const channel = AndroidNotificationChannel(
          BaseQuranDownloadNotificationService.kDownloadNotificationChannelId,
          BaseQuranDownloadNotificationService.kDownloadNotificationChannelName,
          description: BaseQuranDownloadNotificationService
              .kDownloadNotificationChannelDescription,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          enableLights: false,
          showBadge: false,
        );

        await androidImpl?.createNotificationChannel(channel);
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[QuranDownloadNotificationService] Channel initialization error: $e');
    }
  }

  @override
  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required double? progressRatio,
    required bool isOngoing,
    required bool isIndeterminate,
  }) async {
    await initialize();

    final progressPct = (progressRatio != null)
        ? (progressRatio * 100).clamp(0, 100).toInt()
        : 0;

    final androidDetails = AndroidNotificationDetails(
      BaseQuranDownloadNotificationService.kDownloadNotificationChannelId,
      BaseQuranDownloadNotificationService.kDownloadNotificationChannelName,
      channelDescription: BaseQuranDownloadNotificationService
          .kDownloadNotificationChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      onlyAlertOnce: true,
      ongoing: isOngoing,
      autoCancel: !isOngoing,
      showProgress: !isIndeterminate,
      maxProgress: 100,
      progress: progressPct,
      indeterminate: isIndeterminate,
      icon: '@drawable/ic_stat_icon',
    );

    // On iOS, progress bar is not supported in standard local notifications (C1).
    // Avoid spamming user with frequent progress alerts.
    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: 'quran_download_$id',
      );
    } catch (e) {
      debugPrint('[QuranDownloadNotificationService] Failed to show progress notification: $e');
    }
  }

  @override
  Future<void> showTerminalNotification({
    required int id,
    required String title,
    required String body,
    required bool isError,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      BaseQuranDownloadNotificationService.kDownloadNotificationChannelId,
      BaseQuranDownloadNotificationService.kDownloadNotificationChannelName,
      channelDescription: BaseQuranDownloadNotificationService
          .kDownloadNotificationChannelDescription,
      importance: isError ? Importance.defaultImportance : Importance.low,
      priority: isError ? Priority.defaultPriority : Priority.low,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      onlyAlertOnce: true,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      icon: '@drawable/ic_stat_icon',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: 'quran_download_$id',
      );
    } catch (e) {
      debugPrint('[QuranDownloadNotificationService] Failed to show terminal notification: $e');
    }
  }

  @override
  Future<void> dismissNotification(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('[QuranDownloadNotificationService] Failed to dismiss notification #$id: $e');
    }
  }

  @override
  Future<void> dismissSingleSurahNotification() async {
    await dismissNotification(
      BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId,
    );
  }

  @override
  Future<void> dismissQueueNotification() async {
    await dismissNotification(
      BaseQuranDownloadNotificationService.kFullQuranDownloadNotificationId,
    );
  }

  @override
  Future<void> dismissAllQuranDownloadNotifications() async {
    await dismissSingleSurahNotification();
    await dismissQueueNotification();
  }
}
