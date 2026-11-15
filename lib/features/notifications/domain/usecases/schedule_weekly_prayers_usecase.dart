import 'dart:developer';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/calendar_alarm_id_contract.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_scheduling_decision.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleWeeklyPrayersUseCase {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  final GetIqamaDelaysUseCase getIqamaDelaysUseCase;
  final BaseNotificationRepository notificationRepository;
  final SharedPreferences pref;
  final BasePrayerAlarmConfigRepository prayerAlarmConfigRepository;

  static int _scheduleSessionId = 0;

  @visibleForTesting
  static int get currentSessionId => _scheduleSessionId;

  @visibleForTesting
  static void resetSessionIdForTesting() => _scheduleSessionId = 0;

  ScheduleWeeklyPrayersUseCase({
    required this.getPrayerTimesUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.schedulePrayerUseCase,
    required this.getIqamaDelaysUseCase,
    required this.notificationRepository,
    required this.pref,
    required this.prayerAlarmConfigRepository,
  });

  Future<void> execute(double lat, double lng, String city, [String? country]) async {
    // 1. قراءة إعدادات الصلوات الخمس والتحقق الصارم منها قبل أي أثر جانبي
    final rawConfigs = await prayerAlarmConfigRepository.getConfigs();
    final validConfigs = _validateConfigs(rawConfigs);
    log("📋 Validated configurations for ${validConfigs.length} prayers: ${validConfigs.keys.map((k) => k.key).join(', ')}");

    // 2. إدارة التضارب (Race Conditions) - زيادة معرف الجلسة بعد نجاح التحقق فقط
    final int currentSession = ++_scheduleSessionId;
    log("🚀 Starting scheduling session #$currentSession on Main Thread with Throttling...");

    // 3. قراءة الإعدادات
    final iqamaDelays = await getIqamaDelaysUseCase.execute();
    final adhanVolume = pref.getDouble('adhan_volume') ?? 1.0;
    final isAdhanVibrationEnabled = pref.getBool('isAdhanVibrationEnabled') ?? true;
    final isIqamaEnabled = pref.getBool('isIqamaEnabled') ?? true;
    final isAzkarReminderEnabled = pref.getBool('isAzkarReminderEnabled') ?? true;

    // 4. البدء في جدولة الأيام الخمسة بمصالحة مستهدفة (Targeted Reconciliation) دون مسح شامل
    log("📅 Scheduling notifications for the next 5 days with targeted reconciliation...");

    DateTime? lastContiguousCompleteDay;

    for (int i = 0; i < 5; i++) {
      // 4. التأكد من عدم وجود جلسة جديدة بدأت أثناء العمل
      if (_scheduleSessionId != currentSession) {
        log("🛑 Session #$currentSession cancelled because a newer session started.");
        return;
      }

      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day + i);
      
      final result = await getPrayerTimesUseCase(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
        country: country,
      );
      
      final DaySchedulingOutcome dayOutcome = await result.fold(
        (failure) async {
          log("⚠️ Calculation failure for ${date.toLocal()}: $failure");
          return DaySchedulingOutcome.calculationFailure(
            date: date,
            reason: failure.toString(),
          );
        },
        (prayerTimes) async {
          log("📅 Fetched prayer times for ${date.toLocal()} - scheduling...");
          return await _schedulePrayersForDay(
            date: date,
            prayerTimes: prayerTimes,
            prayerConfigs: validConfigs,
            iqamaDelays: iqamaDelays,
            adhanVolume: adhanVolume,
            isAdhanVibrationEnabled: isAdhanVibrationEnabled,
            isIqamaEnabled: isIqamaEnabled,
            isAzkarReminderEnabled: isAzkarReminderEnabled,
            isToday: i == 0,
          );
        },
      );

      if (!dayOutcome.isComplete) {
        final failureReason = dayOutcome.firstFailure?.failureReason ??
            dayOutcome.dayFailureReason ??
            dayOutcome.firstDeferredOperation?.status.name ??
            'Incomplete operations';
        log("🛑 Day ${date.toLocal()} is INCOMPLETE (reason: $failureReason). Halting horizon advancement.");
        break; // Contiguous Horizon Invariant: Abort loop immediately on first incomplete day!
      }

      lastContiguousCompleteDay = date;
      
      // 5. نظام التقطيع (Chunking / Throttling)
      // هذا السطر السحري يحل مشكلتين:
      // - يحرر الـ Dart Main Thread ليرسم الواجهة (يمنع الـ UI Lag)
      // - يمنع اختناق الـ Native Android Thread بكميات هائلة من הـ PendingIntents
      await Future.delayed(const Duration(milliseconds: 150));
    }
    
    if (_scheduleSessionId == currentSession) {
      if (lastContiguousCompleteDay != null) {
        final establishedHorizon = DateTime(
          lastContiguousCompleteDay.year,
          lastContiguousCompleteDay.month,
          lastContiguousCompleteDay.day,
          23,
          59,
          59,
        );

        final storedRaw = pref.getString('scheduled_until_date');
        DateTime? storedHorizon;
        if (storedRaw != null) {
          try {
            final parsed = DateTime.parse(storedRaw);
            if (parsed.year >= 2024 && parsed.year <= 2099) {
              storedHorizon = parsed;
            }
          } catch (_) {
            storedHorizon = null;
          }
        }

        // Monotonic Horizon Update Rules:
        if (storedHorizon == null || establishedHorizon.isAfter(storedHorizon)) {
          await pref.setString('scheduled_until_date', establishedHorizon.toIso8601String());
          log("✅ Horizon advanced to $establishedHorizon");
        } else {
          log("ℹ️ Preserving previously valid stored horizon ($storedHorizon) >= established horizon ($establishedHorizon)");
        }
      } else {
        log("⚠️ Day 0 incomplete: Stored horizon preserved, zero advance.");
      }

      await pref.setInt('last_known_timezone_offset_minutes', DateTime.now().timeZoneOffset.inMinutes);
      log("✅ Scheduling session #$currentSession complete!");
    }
  }

  Future<DaySchedulingOutcome> _schedulePrayersForDay({
    required DateTime date,
    required var prayerTimes, 
    required Map<PrayerId, PrayerAlarmConfig> prayerConfigs,
    required Map<String, int> iqamaDelays,
    required double adhanVolume,
    required bool isAdhanVibrationEnabled,
    required bool isIqamaEnabled,
    required bool isAzkarReminderEnabled,
    required bool isToday,
  }) async {
    final now = DateTime.now();
    final List<ScheduleOperationResult> operations = [];

    // Calculate dynamic expected operations count:
    int expectedCount = 5; // 5 prayer alerts (fajr, dhuhr, asr, maghrib, isha)
    if (isIqamaEnabled) {
      for (final key in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']) {
        if ((iqamaDelays[key] ?? -1) > 0) {
          expectedCount++;
        }
      }
    }
    if (isAzkarReminderEnabled) {
      expectedCount += 5; // post-prayer azkar for each prayer
      expectedCount += 2; // morning and evening azkar
    }

    final prayers = [
      (name: 'الفجر', time: prayerTimes.fajr, key: 'fajr', prayerId: PrayerId.fajr),
      (name: 'الشروق', time: prayerTimes.sunrise, key: 'shurooq', prayerId: null),
      (name: 'الظهر', time: prayerTimes.dhuhr, key: 'dhuhr', prayerId: PrayerId.dhuhr),
      (name: 'العصر', time: prayerTimes.asr, key: 'asr', prayerId: PrayerId.asr),
      (name: 'المغرب', time: prayerTimes.maghrib, key: 'maghrib', prayerId: PrayerId.maghrib),
      (name: 'العشاء', time: prayerTimes.isha, key: 'isha', prayerId: PrayerId.isha),
    ];

    for (var prayer in prayers) {
      if (prayer.time == null || prayer.prayerId == null) continue;

      final config = prayerConfigs[prayer.prayerId!]!;
      final decision = switch (config.alarmType) {
        PrayerAlarmType.alarm => PrayerAlertDecision.alarm,
        PrayerAlarmType.notification => PrayerAlertDecision.notification,
        PrayerAlarmType.off => PrayerAlertDecision.none,
      };

      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: date,
        prayer: prayer.prayerId!,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: date,
        prayer: prayer.prayerId!,
        decision: PrayerAlertDecision.notification,
      );

      // 1. Evaluate Prayer Alert
      if (decision == PrayerAlertDecision.none) {
        // Targeted Decommissioning: Cancel existing Alarm and Notification targetedly
        final alarmCancelStatus = await notificationRepository.cancelAlarmSafely(alarmId);
        final notifCancelStatus = await notificationRepository.cancelNotificationSafely(notifId);
        final details = OffDecommissionDetails(
          alarmId: alarmId,
          alarmStatus: alarmCancelStatus,
          notificationId: notifId,
          notificationStatus: notifCancelStatus,
        );

        if (details.isFullyClean) {
          operations.add(ScheduleOperationResult.skippedOff(
            eventId: null,
            eventType: ScheduleEventType.prayerAlert,
            scheduledTime: prayer.time!,
            offDetails: details,
          ));
        } else if (details.hasFailure) {
          // Failure strictly takes precedence over deferral
          operations.add(ScheduleOperationResult.failed(
            eventId: null,
            eventType: ScheduleEventType.prayerAlert,
            scheduledTime: prayer.time!,
            failureReason:
                'Off decommission failed: alarm=${details.alarmStatus}, notif=${details.notificationStatus}',
            offDetails: details,
          ));
        } else {
          // Deferred due to ringing or imminent protection
          operations.add(ScheduleOperationResult.skippedImminent(
            eventId: null,
            eventType: ScheduleEventType.prayerAlert,
            scheduledTime: prayer.time!,
            offDetails: details,
          ));
        }
      } else {
        final alertId = decision == PrayerAlertDecision.alarm ? alarmId : notifId;

        if (prayer.time!.isBefore(now)) {
          if (isToday) {
            operations.add(ScheduleOperationResult.skippedPast(
              eventId: alertId,
              eventType: ScheduleEventType.prayerAlert,
              scheduledTime: prayer.time!,
            ));
          } else {
            operations.add(ScheduleOperationResult.failed(
              eventId: alertId,
              eventType: ScheduleEventType.prayerAlert,
              scheduledTime: prayer.time!,
              failureReason: 'Future prayer time is in the past: ${prayer.time}',
            ));
          }
        } else {
          // Imminent Window Check: [prayer.time - 15s, prayer.time + 60s]
          final isImminent = !now.isBefore(prayer.time!.subtract(const Duration(seconds: 15))) &&
              !now.isAfter(prayer.time!.add(const Duration(seconds: 60)));
          if (isImminent) {
            operations.add(ScheduleOperationResult.skippedImminent(
              eventId: alertId,
              eventType: ScheduleEventType.prayerAlert,
              scheduledTime: prayer.time!,
            ));
          } else if (decision == PrayerAlertDecision.alarm) {
            log("⏲️ Reconciling ALARM for prayer: ${prayer.name} at ${prayer.time} with deterministic ID #$alertId");

            final effectiveVolume = config.volume ?? adhanVolume;
            final effectiveVibration = config.isVibrationEnabled ?? isAdhanVibrationEnabled;

            // Non-Destructive Audio Source Resolution
            String expectedAsset;
            if (config.audioSource is BuiltInAudioSource) {
              expectedAsset = (config.audioSource as BuiltInAudioSource)
                  .resolveAssetPath(isFajr: prayer.prayerId == PrayerId.fajr);
            } else if (config.audioSource is CustomAudioSource) {
              final custom = config.audioSource as CustomAudioSource;
              final file = File(custom.localRelativePath);
              if (file.existsSync()) {
                expectedAsset = custom.localRelativePath;
              } else {
                log("⚠️ [Scheduler] Custom audio missing at '${custom.localRelativePath}'. Non-destructive fallback to built-in default.");
                expectedAsset = AudioSourceConfig.defaultBuiltInFallback(isFajr: prayer.prayerId == PrayerId.fajr)
                    .resolveAssetPath(isFajr: prayer.prayerId == PrayerId.fajr);
              }
            } else {
              expectedAsset = prayer.name == 'الفجر'
                  ? 'assets/sounds/fajr_azan.mp3'
                  : 'assets/sounds/adhan.mp3';
            }

            final existingStatus = await notificationRepository.verifyAlarm(
              id: alarmId,
              expectedScheduledTime: prayer.time!,
              expectedAssetAudioPath: expectedAsset,
              expectedVolume: effectiveVolume,
              expectedEnableVibration: effectiveVibration,
            );

            if (existingStatus == EventVerificationStatus.unverifiable) {
              // Fail-Closed: do not dispatch, do not decommission
              operations.add(ScheduleOperationResult.failed(
                eventId: alarmId,
                eventType: ScheduleEventType.prayerAlert,
                scheduledTime: prayer.time!,
                failureReason: 'Pre-check verifyAlarm unverifiable for alarm #$alarmId',
              ));
            } else if (existingStatus == EventVerificationStatus.matching) {
              // Matching alert already active: decommission opposing notification
              final decommissionStatus =
                  await notificationRepository.cancelNotificationSafely(notifId);
              if (decommissionStatus.isSuccessful) {
                operations.add(ScheduleOperationResult.skippedMatching(
                  eventId: alarmId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                ));
              } else if (decommissionStatus.isDeferred) {
                operations.add(ScheduleOperationResult.opposingDecommissionDeferred(
                  eventId: alarmId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                ));
              } else {
                operations.add(ScheduleOperationResult.opposingDecommissionFailed(
                  eventId: alarmId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                  failureReason:
                      'Opposing notification decommissioning failed: $decommissionStatus',
                ));
              }
            } else {
              // absent or stale: dispatch scheduleAdhanAlarm
              bool dispatchSuccess = false;
              String? dispatchError;
              try {
                await notificationRepository.scheduleAdhanAlarm(
                  id: alarmId,
                  title: 'حان الآن موعد صلاة ${prayer.name}',
                  body: prayer.name == 'الفجر'
                      ? 'الصلاة خير من النوم'
                      : 'حي على الصلاة، حي على الفلاح',
                  scheduledTime: prayer.time!,
                  assetAudioPath: expectedAsset,
                  volume: effectiveVolume,
                  enableVibration: effectiveVibration,
                );
                dispatchSuccess = true;
              } on PlatformException catch (e) {
                dispatchError = e.message ?? e.toString();
              } on MissingPluginException catch (e) {
                dispatchError = e.message ?? e.toString();
              } catch (e) {
                dispatchError = e.toString();
              }

              if (!dispatchSuccess) {
                // Non-atomic replacement: opposing alert is preserved as safety fallback!
                operations.add(ScheduleOperationResult.failed(
                  eventId: alarmId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                  failureReason: dispatchError ?? 'Alarm dispatch failed',
                ));
              } else {
                // Post-dispatch verification at Level 2
                final postStatus = await notificationRepository.verifyAlarm(
                  id: alarmId,
                  expectedScheduledTime: prayer.time!,
                  expectedAssetAudioPath: expectedAsset,
                  expectedVolume: effectiveVolume,
                  expectedEnableVibration: effectiveVibration,
                );

                if (postStatus == EventVerificationStatus.matching) {
                  // Now decommission opposing notification
                  final decommissionStatus =
                      await notificationRepository.cancelNotificationSafely(notifId);
                  if (decommissionStatus.isSuccessful) {
                    operations.add(ScheduleOperationResult.scheduled(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                    ));
                  } else if (decommissionStatus.isDeferred) {
                    operations.add(ScheduleOperationResult.opposingDecommissionDeferred(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                    ));
                  } else {
                    operations.add(ScheduleOperationResult.opposingDecommissionFailed(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                      failureReason:
                          'Opposing notification decommissioning failed: $decommissionStatus',
                    ));
                  }
                } else {
                  // Post-verification failed (absent, stale, or unverifiable)
                  operations.add(ScheduleOperationResult.failed(
                    eventId: alertId,
                    eventType: ScheduleEventType.prayerAlert,
                    scheduledTime: prayer.time!,
                    failureReason: 'Post-dispatch verifyAlarm returned $postStatus',
                  ));
                }
              }
            }
          } else if (decision == PrayerAlertDecision.notification) {
            log("⏲️ Reconciling NOTIFICATION for prayer: ${prayer.name} at ${prayer.time} with deterministic ID #$alertId");
            final expectedSound = prayer.name == 'الفجر' ? 'fajr_azan' : 'adhan';
            final expectedChannel = 'prayer_channel_v10_$expectedSound';
            final expectedTitle = 'حان الآن موعد صلاة ${prayer.name}';
            final expectedBody = prayer.name == 'الفجر'
                ? 'الصلاة خير من النوم'
                : 'حي على الصلاة، حي على الفلاح';
            final expectedPayload = NotificationPayloadContract.buildPayload(
              eventId: notifId,
              scheduledTime: prayer.time!,
              channelId: expectedChannel,
              soundSource: expectedSound,
              title: expectedTitle,
              body: expectedBody,
            );

            final existingStatus = await notificationRepository.verifyNotification(
              id: notifId,
              expectedScheduledTime: prayer.time!,
              expectedPayload: expectedPayload,
              expectedTitle: expectedTitle,
              expectedBody: expectedBody,
              expectedChannelId: expectedChannel,
              expectedSoundSource: expectedSound,
            );

            if (existingStatus == EventVerificationStatus.unverifiable) {
              // Fail-Closed: do not dispatch, do not decommission
              operations.add(ScheduleOperationResult.failed(
                eventId: notifId,
                eventType: ScheduleEventType.prayerAlert,
                scheduledTime: prayer.time!,
                failureReason:
                    'Pre-check verifyNotification unverifiable for notif #$notifId',
              ));
            } else if (existingStatus == EventVerificationStatus.matching) {
              // Matching notification already active: decommission opposing alarm
              final decommissionStatus =
                  await notificationRepository.cancelAlarmSafely(alarmId);
              if (decommissionStatus.isSuccessful) {
                operations.add(ScheduleOperationResult.skippedMatching(
                  eventId: notifId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                ));
              } else if (decommissionStatus.isDeferred) {
                operations.add(ScheduleOperationResult.opposingDecommissionDeferred(
                  eventId: notifId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                ));
              } else {
                operations.add(ScheduleOperationResult.opposingDecommissionFailed(
                  eventId: notifId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                  failureReason:
                      'Opposing alarm decommissioning failed: $decommissionStatus',
                ));
              }
            } else {
              // absent or stale: dispatch schedulePrayerNotification
              bool dispatchSuccess = false;
              String? dispatchError;
              try {
                await notificationRepository.schedulePrayerNotification(
                  id: notifId,
                  title: expectedTitle,
                  body: expectedBody,
                  scheduledTime: prayer.time!,
                  soundName: expectedSound,
                  payload: expectedPayload,
                );
                dispatchSuccess = true;
              } on PlatformException catch (e) {
                dispatchError = e.message ?? e.toString();
              } on MissingPluginException catch (e) {
                dispatchError = e.message ?? e.toString();
              } catch (e) {
                dispatchError = e.toString();
              }

              if (!dispatchSuccess) {
                // Non-atomic replacement: opposing alert is preserved as safety fallback!
                operations.add(ScheduleOperationResult.failed(
                  eventId: notifId,
                  eventType: ScheduleEventType.prayerAlert,
                  scheduledTime: prayer.time!,
                  failureReason: dispatchError ?? 'Notification dispatch failed',
                ));
              } else {
                // Post-dispatch verification at Level 2
                final postStatus = await notificationRepository.verifyNotification(
                  id: notifId,
                  expectedScheduledTime: prayer.time!,
                  expectedPayload: expectedPayload,
                  expectedTitle: expectedTitle,
                  expectedBody: expectedBody,
                  expectedChannelId: expectedChannel,
                  expectedSoundSource: expectedSound,
                );

                if (postStatus == EventVerificationStatus.matching) {
                  // Now decommission opposing alarm
                  final decommissionStatus =
                      await notificationRepository.cancelAlarmSafely(alarmId);
                  if (decommissionStatus.isSuccessful) {
                    operations.add(ScheduleOperationResult.scheduled(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                    ));
                  } else if (decommissionStatus.isDeferred) {
                    operations.add(ScheduleOperationResult.opposingDecommissionDeferred(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                    ));
                  } else {
                    operations.add(ScheduleOperationResult.opposingDecommissionFailed(
                      eventId: alertId,
                      eventType: ScheduleEventType.prayerAlert,
                      scheduledTime: prayer.time!,
                      failureReason:
                          'Opposing alarm decommissioning failed: $decommissionStatus',
                    ));
                  }
                } else {
                  // Post-verification failed
                  operations.add(ScheduleOperationResult.failed(
                    eventId: alertId,
                    eventType: ScheduleEventType.prayerAlert,
                    scheduledTime: prayer.time!,
                    failureReason:
                        'Post-dispatch verifyNotification returned $postStatus',
                  ));
                }
              }
            }
          }
        }
      }

      // 2. Evaluate Iqama
      final int iqamaDelay = iqamaDelays[prayer.key] ?? -1;
      if (isIqamaEnabled && iqamaDelay > 0) {
        final DateTime iqamaTime = prayer.time!.add(Duration(minutes: iqamaDelay));
        final iqamaAlertId = CalendarAlarmIdContract.iqamaId(
          date: date,
          prayer: prayer.prayerId!,
        );

        if (iqamaTime.isBefore(now)) {
          if (isToday) {
            operations.add(ScheduleOperationResult.skippedPast(
              eventId: iqamaAlertId,
              eventType: ScheduleEventType.iqama,
              scheduledTime: iqamaTime,
            ));
          } else {
            operations.add(ScheduleOperationResult.failed(
              eventId: iqamaAlertId,
              eventType: ScheduleEventType.iqama,
              scheduledTime: iqamaTime,
              failureReason: 'Future Iqama time is in past',
            ));
          }
        } else {
          try {
            String? customIqamaPath;
            final config = prayerConfigs[prayer.prayerId];
            if (config != null && config.audioSource is CustomAudioSource) {
              final custom = config.audioSource as CustomAudioSource;
              if (custom.iqamaLocalRelativePath != null) {
                final file = File(custom.iqamaLocalRelativePath!);
                if (file.existsSync()) {
                  customIqamaPath = custom.iqamaLocalRelativePath;
                }
              }
            }

            if (customIqamaPath != null) {
              // Custom Iqama audio exists on disk: schedule via alarm without full screen (notification only)
              await notificationRepository.scheduleAdhanAlarm(
                id: iqamaAlertId,
                title: 'إقامة صلاة ${prayer.name}',
                body: 'تجهز للصلاة، ستقام الصلاة الآن',
                scheduledTime: iqamaTime,
                assetAudioPath: customIqamaPath,
                androidFullScreenIntent: false,
                stopButton: null,
              );
            } else {
              // Default built-in iqama: standard notification
              await notificationRepository.schedulePrayerNotification(
                id: iqamaAlertId,
                title: 'إقامة صلاة ${prayer.name}',
                body: 'تجهز للصلاة، ستقام الصلاة الآن',
                scheduledTime: iqamaTime,
                soundName: 'iqama_sound',
                payload: 'iqama_${iqamaAlertId}_${prayer.name}',
              );
            }
            operations.add(ScheduleOperationResult.scheduled(
              eventId: iqamaAlertId,
              eventType: ScheduleEventType.iqama,
              scheduledTime: iqamaTime,
            ));
          } on PlatformException catch (e) {
            operations.add(ScheduleOperationResult.failed(
              eventId: iqamaAlertId,
              eventType: ScheduleEventType.iqama,
              scheduledTime: iqamaTime,
              failureReason: e.message ?? e.toString(),
            ));
          } on MissingPluginException catch (e) {
            operations.add(ScheduleOperationResult.failed(
              eventId: iqamaAlertId,
              eventType: ScheduleEventType.iqama,
              scheduledTime: iqamaTime,
              failureReason: e.message ?? e.toString(),
            ));
          }
        }
      }

      // 3. Evaluate Post-Prayer Azkar
      if (isAzkarReminderEnabled) {
        DateTime azkarAfterPrayerTime;
        if (isIqamaEnabled && iqamaDelay > 0) {
          azkarAfterPrayerTime = prayer.time!.add(Duration(minutes: iqamaDelay + 5));
        } else {
          azkarAfterPrayerTime = prayer.time!.add(const Duration(minutes: 25));
        }

        final azkarAlertId = CalendarAlarmIdContract.postPrayerAzkarId(
          date: date,
          prayer: prayer.prayerId!,
        );

        if (azkarAfterPrayerTime.isBefore(now)) {
          if (isToday) {
            operations.add(ScheduleOperationResult.skippedPast(
              eventId: azkarAlertId,
              eventType: ScheduleEventType.postPrayerAzkar,
              scheduledTime: azkarAfterPrayerTime,
            ));
          } else {
            operations.add(ScheduleOperationResult.failed(
              eventId: azkarAlertId,
              eventType: ScheduleEventType.postPrayerAzkar,
              scheduledTime: azkarAfterPrayerTime,
              failureReason: 'Future Azkar time is in past',
            ));
          }
        } else {
          try {
            await notificationRepository.schedulePrayerNotification(
              id: azkarAlertId,
              title: 'أذكار بعد الصلاة',
              body: 'تقبل الله صلاتك، لا تنس أذكار ما بعد صلاة ${prayer.name}.',
              scheduledTime: azkarAfterPrayerTime,
              payload: 'azkar_after_prayer',
            );
            operations.add(ScheduleOperationResult.scheduled(
              eventId: azkarAlertId,
              eventType: ScheduleEventType.postPrayerAzkar,
              scheduledTime: azkarAfterPrayerTime,
            ));
          } on PlatformException catch (e) {
            operations.add(ScheduleOperationResult.failed(
              eventId: azkarAlertId,
              eventType: ScheduleEventType.postPrayerAzkar,
              scheduledTime: azkarAfterPrayerTime,
              failureReason: e.message ?? e.toString(),
            ));
          } on MissingPluginException catch (e) {
            operations.add(ScheduleOperationResult.failed(
              eventId: azkarAlertId,
              eventType: ScheduleEventType.postPrayerAzkar,
              scheduledTime: azkarAfterPrayerTime,
              failureReason: e.message ?? e.toString(),
            ));
          }
        }

        // 4. Morning Azkar (Fajr)
        if (prayer.prayerId == PrayerId.fajr) {
          final specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          final morningAlertId = CalendarAlarmIdContract.morningAzkarId(date: date);

          if (specificAzkarTime.isBefore(now)) {
            if (isToday) {
              operations.add(ScheduleOperationResult.skippedPast(
                eventId: morningAlertId,
                eventType: ScheduleEventType.morningAzkar,
                scheduledTime: specificAzkarTime,
              ));
            } else {
              operations.add(ScheduleOperationResult.failed(
                eventId: morningAlertId,
                eventType: ScheduleEventType.morningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: 'Future Morning Azkar in past',
              ));
            }
          } else {
            try {
              await notificationRepository.schedulePrayerNotification(
                id: morningAlertId,
                title: 'أذكار الصباح',
                body: 'حان وقت أذكار الصباح، احفظ عهدك مع الله.',
                scheduledTime: specificAzkarTime,
                payload: 'azkar_morning',
              );
              operations.add(ScheduleOperationResult.scheduled(
                eventId: morningAlertId,
                eventType: ScheduleEventType.morningAzkar,
                scheduledTime: specificAzkarTime,
              ));
            } on PlatformException catch (e) {
              operations.add(ScheduleOperationResult.failed(
                eventId: morningAlertId,
                eventType: ScheduleEventType.morningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: e.message ?? e.toString(),
              ));
            } on MissingPluginException catch (e) {
              operations.add(ScheduleOperationResult.failed(
                eventId: morningAlertId,
                eventType: ScheduleEventType.morningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: e.message ?? e.toString(),
              ));
            }
          }
        } else if (prayer.prayerId == PrayerId.asr) {
          // 5. Evening Azkar (Asr)
          final specificAzkarTime = prayer.time!.add(const Duration(minutes: 30));
          final eveningAlertId = CalendarAlarmIdContract.eveningAzkarId(date: date);

          if (specificAzkarTime.isBefore(now)) {
            if (isToday) {
              operations.add(ScheduleOperationResult.skippedPast(
                eventId: eveningAlertId,
                eventType: ScheduleEventType.eveningAzkar,
                scheduledTime: specificAzkarTime,
              ));
            } else {
              operations.add(ScheduleOperationResult.failed(
                eventId: eveningAlertId,
                eventType: ScheduleEventType.eveningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: 'Future Evening Azkar in past',
              ));
            }
          } else {
            try {
              await notificationRepository.schedulePrayerNotification(
                id: eveningAlertId,
                title: 'أذكار المساء',
                body: 'حان وقت أذكار المساء، احفظ عهدك مع الله.',
                scheduledTime: specificAzkarTime,
                payload: 'azkar_evening',
              );
              operations.add(ScheduleOperationResult.scheduled(
                eventId: eveningAlertId,
                eventType: ScheduleEventType.eveningAzkar,
                scheduledTime: specificAzkarTime,
              ));
            } on PlatformException catch (e) {
              operations.add(ScheduleOperationResult.failed(
                eventId: eveningAlertId,
                eventType: ScheduleEventType.eveningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: e.message ?? e.toString(),
              ));
            } on MissingPluginException catch (e) {
              operations.add(ScheduleOperationResult.failed(
                eventId: eveningAlertId,
                eventType: ScheduleEventType.eveningAzkar,
                scheduledTime: specificAzkarTime,
                failureReason: e.message ?? e.toString(),
              ));
            }
          }
        }
      }
    }

    return DaySchedulingOutcome(
      date: date,
      operations: operations,
      expectedOperationsCount: expectedCount,
    );
  }

  Map<PrayerId, PrayerAlarmConfig> _validateConfigs(Map<PrayerId, PrayerAlarmConfig>? rawConfigs) {
    if (rawConfigs == null || rawConfigs.length != PrayerId.values.length) {
      throw StateError(
        'Incomplete or invalid prayer configurations. Expected exactly ${PrayerId.values.length}, received ${rawConfigs?.length ?? 0}.',
      );
    }

    for (final prayerId in PrayerId.values) {
      if (!rawConfigs.containsKey(prayerId)) {
        throw StateError('Missing configuration for mandatory prayer: ${prayerId.key}');
      }
    }

    for (final entry in rawConfigs.entries) {
      if (entry.key != entry.value.prayerId) {
        throw StateError(
          'Mismatched PrayerId for ${entry.key.key}: key indicates ${entry.key.key} but entity holds ${entry.value.prayerId.key}.',
        );
      }
      if (!PrayerAlarmType.values.contains(entry.value.alarmType)) {
        throw StateError('Invalid alarm type for prayer ${entry.key.key}: ${entry.value.alarmType}');
      }
    }

    return Map<PrayerId, PrayerAlarmConfig>.unmodifiable(rawConfigs);
  }
}
