import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

StreamController<String> selectNotificationStream =
    StreamController<String>.broadcast();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // يشتغل والتطبيق مقفول تماماً
  print('🔔 Background Notification Tapped: ${notificationResponse.payload}');
}

void onDidReceiveNotificationResponse(
  NotificationResponse notificationResponse,
) {
  print('🔔 Notification Tapped: ${notificationResponse.payload}');

  if (notificationResponse.id != null && notificationResponse.payload != null) {
    selectNotificationStream.add(notificationResponse.payload!);
  }
}

/// Persistent ledger model representing verified notification application metadata.
class NotificationFingerprint {
  final int eventId;
  final DateTime scheduledTime;
  final String configDigest;
  final String payload;

  const NotificationFingerprint({
    required this.eventId,
    required this.scheduledTime,
    required this.configDigest,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'scheduledTimeEpochMs': scheduledTime.millisecondsSinceEpoch,
        'configDigest': configDigest,
        'payload': payload,
      };

  factory NotificationFingerprint.fromJson(Map<String, dynamic> json) =>
      NotificationFingerprint(
        eventId: json['eventId'] as int,
        scheduledTime: DateTime.fromMillisecondsSinceEpoch(
            json['scheduledTimeEpochMs'] as int),
        configDigest: json['configDigest'] as String,
        payload: json['payload'] as String,
      );
}

/// Canonical JSON serialization and deterministic 64-bit truncated SHA-256 correlation digest.
class NotificationPayloadContract {
  /// Serializes configuration into an injective, escaped Canonical JSON string.
  static String canonicalSerializeConfig({
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    final map = <String, String>{
      'bdy': body,
      'chn': channelId,
      'snd': soundSource,
      'ttl': title,
    };
    return jsonEncode(map);
  }

  /// Computes a deterministic 64-bit truncated SHA-256 correlation fingerprint.
  static String computeConfigDigest({
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    final canonicalJson = canonicalSerializeConfig(
      channelId: channelId,
      soundSource: soundSource,
      title: title,
      body: body,
    );
    final bytes = utf8.encode(canonicalJson);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Builds the composite payload string passed to FLN and stored in SharedPreferences.
  static String buildPayload({
    required int eventId,
    required DateTime scheduledTime,
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
    int generation = 1,
  }) {
    final digest = computeConfigDigest(
      channelId: channelId,
      soundSource: soundSource,
      title: title,
      body: body,
    );
    final timeEpoch = scheduledTime.millisecondsSinceEpoch;
    return 'prayer_${eventId}_g${generation}_t${timeEpoch}_$digest';
  }

  /// Parses and validates the structured payload components.
  static ParsedPayload? parsePayload(String? payload) {
    if (payload == null) return null;
    final regex = RegExp(r'^prayer_(\d+)_g(\d+)_t(\d+)_([0-9a-fA-F]{16})$');
    final match = regex.firstMatch(payload);
    if (match == null) return null;

    return ParsedPayload(
      eventId: int.parse(match.group(1)!),
      generation: int.parse(match.group(2)!),
      scheduledTimeEpochMs: int.parse(match.group(3)!),
      configDigest: match.group(4)!,
    );
  }
}

class ParsedPayload {
  final int eventId;
  final int generation;
  final int scheduledTimeEpochMs;
  final String configDigest;

  const ParsedPayload({
    required this.eventId,
    required this.generation,
    required this.scheduledTimeEpochMs,
    required this.configDigest,
  });
}

class NotificationRepositoryImpl implements BaseNotificationRepository {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  final SharedPreferences? _injectedPrefs;

  NotificationRepositoryImpl({
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferences? prefs,
  })  : flutterLocalNotificationsPlugin =
            plugin ?? FlutterLocalNotificationsPlugin(),
        _injectedPrefs = prefs;

  Future<SharedPreferences> get _prefs async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  bool _isDomainException(Object e) =>
      e is ArgumentError ||
      e is RangeError ||
      e is TypeError ||
      e is AssertionError ||
      e is StateError;

  bool isWithinImminentWindow(DateTime actualScheduledTime, DateTime now) {
    final start = actualScheduledTime.subtract(const Duration(seconds: 15));
    final end = actualScheduledTime.add(const Duration(seconds: 60));
    return !now.isBefore(start) && !now.isAfter(end);
  }

  @override
  Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_stat_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'Hafiz Al Ahd',
      appUserModelId: '234567890',
      guid: '12345678-1234-5678-1234-567812345678',
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      windows: initializationSettingsWindows,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  @override
  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();

    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  @override
  Future<void> schedulePrayerNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) {
      log('ℹ️ [schedulePrayerNotification] Skipped scheduling notification #$id in the past: $scheduledTime');
      return;
    }

    final String channelId = soundName != null
        ? 'prayer_channel_v10_$soundName'
        : 'prayer_channel_v10_default';
    final String soundSource = soundName ?? 'default';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      'إشعارات الصلاة',
      channelDescription: 'إشعارات التنبيه بأوقات الصلاة والإقامة',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: soundName != null
          ? RawResourceAndroidNotificationSound(soundName)
          : null,
      audioAttributesUsage: AudioAttributesUsage.notification,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: false,
      ticker: 'مواقيت الصلاة',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      timeoutAfter: 30 * 60 * 1000,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      enableLights: true,
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true,
      sound: soundName != null ? '$soundName.mp3' : null,
    );

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    final NotificationDetails platformSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      windows: windowsDetails,
    );

    final String payloadData = payload ??
        NotificationPayloadContract.buildPayload(
          eventId: id,
          scheduledTime: scheduledTime,
          channelId: channelId,
          soundSource: soundSource,
          title: title,
          body: body,
        );

    // Save persistent ledger entry
    try {
      final p = await _prefs;
      final digest = NotificationPayloadContract.computeConfigDigest(
        channelId: channelId,
        soundSource: soundSource,
        title: title,
        body: body,
      );
      final fp = NotificationFingerprint(
        eventId: id,
        scheduledTime: scheduledTime,
        configDigest: digest,
        payload: payloadData,
      );
      await p.setString('notif_fingerprint_$id', jsonEncode(fp.toJson()));
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      log('⚠️ [schedulePrayerNotification] Failed to record persistent fingerprint: $e');
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final delay = scheduledTime.difference(DateTime.now());
      if (!delay.isNegative) {
        Timer(delay, () async {
          await flutterLocalNotificationsPlugin.show(
            id: id,
            title: title,
            body: body,
            notificationDetails: platformSpecifics,
            payload: payloadData,
          );
        });
      }
      return;
    }

    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      tz.local,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduledTime,
      notificationDetails: platformSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payloadData,
    );
  }

  @override
  Future<int> getPendingNotificationsCount() async {
    final pendingRequests =
        await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    return pendingRequests.length;
  }

  @override
  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  @override
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    final List<ActiveNotification> activeNotifications =
        await flutterLocalNotificationsPlugin.getActiveNotifications();

    for (var active in activeNotifications) {
      if (active.channelId != null &&
          active.channelId!.contains('prayer_channel_v9')) {
        await flutterLocalNotificationsPlugin.cancel(id: active.id ?? -1);
      }
    }
  }

  @override
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) return;

    return await schedulePrayerNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
      payload: payload,
    );
  }

  @override
  Future<void> showStickyNotification({
    required int id,
    required String title,
    required String body,
    required DateTime nextPrayerTime,
  }) async {
    FlutterBackgroundService().invoke('updatePrayerNotification', {
      'title': title,
      'body': body,
      'nextPrayerTimeMs': nextPrayerTime.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> scheduleAdhanAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String assetAudioPath,
    double? volume,
    bool enableVibration = true,
  }) async {
    if (id != 888 && scheduledTime.isBefore(DateTime.now())) {
      log('ℹ️ [scheduleAdhanAlarm] Skipped scheduling alarm #$id in the past: $scheduledTime');
      return;
    }

    if (id != 888 &&
        scheduledTime.difference(DateTime.now()).inMinutes < 1 &&
        scheduledTime.isBefore(
          DateTime.now().add(const Duration(minutes: 1)),
        )) {
      return;
    }

    final alarmSettings = AlarmSettings(
      id: id,
      dateTime: scheduledTime,
      assetAudioPath: assetAudioPath,
      loopAudio: false,
      vibrate: enableVibration,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      volumeSettings: volume == 0.0
          ? VolumeSettings.fade(
              volume: 0.0,
              fadeDuration: const Duration(milliseconds: 1),
            )
          : VolumeSettings.fade(
              volume: volume,
              fadeDuration: const Duration(seconds: 5),
              volumeEnforced: false,
            ),
      notificationSettings: NotificationSettings(
        title: title,
        body: body,
        stopButton: 'إيقاف الأذان',
        icon: 'ic_stat_icon',
      ),
    );

    await Alarm.set(alarmSettings: alarmSettings);
    log('🔔 Scheduled Adhan alarm #$id at $scheduledTime ($assetAudioPath)');
  }

  @override
  Future<void> cancelAllAlarms() async {
    await Alarm.stopAll();
    log('🛑 All Adhan alarms stopped');
  }

  @override
  Future<EventCancellationStatus> cancelAlarmSafely(
    int id, {
    DateTime? expectedScheduledTime,
    String? expectedAssetAudioPath,
  }) async {
    try {
      // 0. Validate ID Range
      final isLegacyPrayerId = id >= 1 && id <= 100;
      final isModernPrayerId = id >= 24010100 && id <= 99123149;
      if (!isLegacyPrayerId && !isModernPrayerId) {
        return EventCancellationStatus.failed;
      }

      // 1. Ringing Audio Guard (Strictly Pre-Destructive)
      bool isRinging = false;
      try {
        isRinging = await Alarm.isRinging(id);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }
      if (isRinging) {
        log('🛑 [cancelAlarmSafely] Suppressed: Alarm #$id is actively ringing');
        return EventCancellationStatus.deferredRinging;
      }

      // 2. Pre-Query Registry
      AlarmSettings? alarm;
      try {
        alarm = await Alarm.getAlarm(id);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }
      if (alarm == null) {
        return EventCancellationStatus.alreadyAbsent;
      }

      // Asset ownership validation
      const validPrayerAssets = {'assets/sounds/adhan.mp3', 'assets/sounds/fajr_azan.mp3'};
      if (expectedAssetAudioPath != null) {
        if (alarm.assetAudioPath != expectedAssetAudioPath) {
          return EventCancellationStatus.failed;
        }
      } else {
        if (!validPrayerAssets.contains(alarm.assetAudioPath)) {
          return EventCancellationStatus.failed;
        }
      }

      // Expected scheduled time drift validation
      if (expectedScheduledTime != null) {
        final driftSeconds = (alarm.dateTime.difference(expectedScheduledTime)).inSeconds.abs();
        if (driftSeconds > 60) {
          return EventCancellationStatus.failed;
        }
      }

      // 3. Temporal Proximity Guard (Actual registered alarm.dateTime)
      if (isWithinImminentWindow(alarm.dateTime, DateTime.now())) {
        log('🛑 [cancelAlarmSafely] Suppressed: Alarm #$id is within temporal guard window');
        return EventCancellationStatus.deferredImminent;
      }

      // 4. Cancellation Execution Call
      try {
        await Alarm.stop(id);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.failed;
      }

      // 5. Post-Query Verification Call
      AlarmSettings? postCheck;
      try {
        postCheck = await Alarm.getAlarm(id);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }

      // 6. Registry Absence Confirmation
      if (postCheck == null) {
        return EventCancellationStatus.cancelled;
      } else {
        return EventCancellationStatus.failed;
      }
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.failed;
    }
  }

  @override
  Future<EventCancellationStatus> cancelNotificationSafely(int id) async {
    try {
      final p = await _prefs;

      // 1. Pre-Query FLN Pending Queue
      List<PendingNotificationRequest> pendingRequests;
      try {
        pendingRequests =
            await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }

      final request = pendingRequests.cast<PendingNotificationRequest?>().firstWhere(
            (r) => r?.id == id,
            orElse: () => null,
          );

      // Path A: Native request is absent from FLN queue
      if (request == null) {
        final hasFingerprint = p.containsKey('notif_fingerprint_$id');
        if (!hasFingerprint) {
          return EventCancellationStatus.alreadyAbsent; // Clean state
        }
        try {
          final removed = await p.remove('notif_fingerprint_$id');
          return removed
              ? EventCancellationStatus.alreadyAbsent
              : EventCancellationStatus.failed;
        } catch (e) {
          if (_isDomainException(e)) rethrow;
          return EventCancellationStatus.failed;
        }
      }

      // Path B: Native request is present in FLN queue
      // Strict 4-Way Mutual Identity Binding Check
      final parsed = NotificationPayloadContract.parsePayload(request.payload);
      if (parsed == null || parsed.eventId != id || parsed.eventId != request.id) {
        return EventCancellationStatus.unverifiable;
      }

      final fpJson = p.getString('notif_fingerprint_$id');
      if (fpJson == null) {
        return EventCancellationStatus.unverifiable;
      }

      NotificationFingerprint fp;
      try {
        fp = NotificationFingerprint.fromJson(
            jsonDecode(fpJson) as Map<String, dynamic>);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }

      if (fp.eventId != id ||
          fp.payload != request.payload ||
          parsed.scheduledTimeEpochMs !=
              fp.scheduledTime.millisecondsSinceEpoch ||
          parsed.configDigest != fp.configDigest) {
        return EventCancellationStatus.unverifiable;
      }

      // Temporal Proximity Guard (Actual validated scheduledTime)
      if (isWithinImminentWindow(fp.scheduledTime, DateTime.now())) {
        return EventCancellationStatus.deferredImminent;
      }

      // 2. Cancellation Execution Call
      try {
        await flutterLocalNotificationsPlugin.cancel(id: id);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.failed;
      }

      // 3. Post-Query Verification Call: Confirm native request removal
      List<PendingNotificationRequest> postRequests;
      try {
        postRequests =
            await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.unverifiable;
      }

      if (postRequests.any((r) => r.id == id)) {
        return EventCancellationStatus.failed;
      }

      // 4. Ledger Removal (executed ONLY after confirmed native removal)
      try {
        final removed = await p.remove('notif_fingerprint_$id');
        if (!removed) {
          return EventCancellationStatus.failed;
        }
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.failed;
      }

      return EventCancellationStatus.cancelled;
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.failed;
    }
  }

  @override
  Future<EventVerificationStatus> verifyAlarm({
    required int id,
    required DateTime expectedScheduledTime,
    String? expectedAssetAudioPath,
    double? expectedVolume,
    bool? expectedEnableVibration,
  }) async {
    try {
      final alarm = await Alarm.getAlarm(id);
      if (alarm == null) {
        return EventVerificationStatus.absent;
      }

      final timeMatches =
          alarm.dateTime.difference(expectedScheduledTime).inSeconds.abs() <= 1;
      final assetMatches = expectedAssetAudioPath == null ||
          alarm.assetAudioPath == expectedAssetAudioPath;
      final vibrationMatches = expectedEnableVibration == null ||
          alarm.vibrate == expectedEnableVibration;

      if (timeMatches && assetMatches && vibrationMatches) {
        return EventVerificationStatus.matching;
      } else {
        return EventVerificationStatus.stale;
      }
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventVerificationStatus.unverifiable;
    }
  }

  @override
  Future<EventVerificationStatus> verifyNotification({
    required int id,
    required DateTime expectedScheduledTime,
    required String expectedPayload,
    String? expectedTitle,
    String? expectedBody,
    String? expectedChannelId,
    String? expectedSoundSource,
  }) async {
    try {
      final p = await _prefs;
      final pendingRequests =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      final request = pendingRequests.cast<PendingNotificationRequest?>().firstWhere(
            (r) => r?.id == id,
            orElse: () => null,
          );

      if (request == null) {
        return EventVerificationStatus.absent;
      }

      // Tier 1: FLN Pending Request Payload Check
      if (request.payload != expectedPayload) {
        return EventVerificationStatus.stale;
      }

      // Tier 2: Persistent Fingerprint Check
      final fpJson = p.getString('notif_fingerprint_$id');
      if (fpJson == null) {
        return EventVerificationStatus.stale;
      }

      NotificationFingerprint fp;
      try {
        fp = NotificationFingerprint.fromJson(
            jsonDecode(fpJson) as Map<String, dynamic>);
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventVerificationStatus.unverifiable;
      }

      final parsed = NotificationPayloadContract.parsePayload(request.payload);
      if (parsed == null) {
        return EventVerificationStatus.stale;
      }

      final idMatches =
          request.id == id && parsed.eventId == id && fp.eventId == id;
      final payloadMatches =
          request.payload == fp.payload && fp.payload == expectedPayload;
      final timeMatches =
          fp.scheduledTime.difference(expectedScheduledTime).inSeconds.abs() <=
                  1 &&
              parsed.scheduledTimeEpochMs ==
                  fp.scheduledTime.millisecondsSinceEpoch;

      if (idMatches && payloadMatches && timeMatches) {
        return EventVerificationStatus.matching;
      } else {
        return EventVerificationStatus.stale;
      }
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventVerificationStatus.unverifiable;
    }
  }
}
