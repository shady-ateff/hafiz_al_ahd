import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alert_transition_record.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';

class FakeConfigRepo implements BasePrayerAlarmConfigRepository {
  final Map<PrayerId, PrayerAlarmConfig> configs = {};

  FakeConfigRepo({PrayerAlarmType initialMode = PrayerAlarmType.alarm}) {
    for (final id in PrayerId.values) {
      configs[id] = PrayerAlarmConfig(prayerId: id, alarmType: initialMode);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late PrayerAlertTransitionLocalDataSourceImpl transitionDataSource;
  late FakeConfigRepo configRepo;

  // Recorded adapter calls
  late List<int> stoppedAlarmIds;
  late List<int> cancelledAlarmIds;
  late List<int> cancelledNotifIds;
  late List<DateTime> scheduledAlarmTimes;
  late List<DateTime> scheduledNotifTimes;

  // Injection controls
  EventCancellationStatus nextAlarmCancelStatus = EventCancellationStatus.cancelled;
  bool shouldThrowOnSchedule = false;

  late DateTime simulatedNow;
  late List<DateTime> fiveDayTimes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    transitionDataSource = PrayerAlertTransitionLocalDataSourceImpl(prefs: prefs);
    configRepo = FakeConfigRepo(initialMode: PrayerAlarmType.alarm);

    stoppedAlarmIds = [];
    cancelledAlarmIds = [];
    cancelledNotifIds = [];
    scheduledAlarmTimes = [];
    scheduledNotifTimes = [];

    nextAlarmCancelStatus = EventCancellationStatus.cancelled;
    shouldThrowOnSchedule = false;

    simulatedNow = DateTime(2026, 11, 10, 12, 0, 0);
    fiveDayTimes = List.generate(
      5,
      (i) => DateTime(2026, 11, 10 + i, 12, 15, 0),
    );
  });

  TransitionCoordinator createCoordinator() {
    return TransitionCoordinator(
      configRepository: configRepo,
      transitionDataSource: transitionDataSource,
      cancelAlarmSafely: (id, {expectedScheduledTime, expectedAssetAudioPath}) async {
        cancelledAlarmIds.add(id);
        return nextAlarmCancelStatus;
      },
      stopActiveAlarm: (id) async {
        stoppedAlarmIds.add(id);
      },
      cancelNotificationSafely: (id) async {
        cancelledNotifIds.add(id);
        return EventCancellationStatus.cancelled;
      },
      scheduleAlarm: (prayerId, dt, audio, vol, vib) async {
        if (shouldThrowOnSchedule) throw Exception('Disk I/O error');
        scheduledAlarmTimes.add(dt);
      },
      scheduleNotification: (prayerId, dt) async {
        if (shouldThrowOnSchedule) throw Exception('FLN scheduling error');
        scheduledNotifTimes.add(dt);
      },
      getPrayerTimesForHorizon: (prayerId) async => fiveDayTimes,
      nowProvider: () => simulatedNow,
    );
  }

  group('P4.1-C.2 — TransitionCoordinator Lifecycle, Concurrency & Recovery', () {
    // -------------------------------------------------------------------------
    // TEST-C-07: Normal Alarm -> Notification transition
    // -------------------------------------------------------------------------
    test('TEST-C-07: Home Toggle Alarm -> Notification (Normal) completes across 5 days', () async {
      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.dhuhr,
        targetMode: PrayerAlarmType.notification,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isCompleted, isTrue);
      expect(result.isDeferred, isFalse);

      // Alarms cancelled across 5 days
      expect(cancelledAlarmIds.length, equals(5));
      // Notifications scheduled across 5 days
      expect(scheduledNotifTimes.length, equals(5));

      // Config updated
      final config = await configRepo.getConfig(PrayerId.dhuhr);
      expect(config.alarmType, equals(PrayerAlarmType.notification));

      // Transition record purged upon completion
      final record = await transitionDataSource.getRecord(PrayerId.dhuhr);
      expect(record, isNull);
    });

    test('Transition when Day 0 is in the past skips Day 0 and schedules remaining future days', () async {
      // Simulate today's prayer occurred earlier today (e.g. Fajr at 05:00 while now is 12:00)
      fiveDayTimes[0] = simulatedNow.subtract(const Duration(hours: 7));

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.fajr,
        targetMode: PrayerAlarmType.notification,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isCompleted, isTrue);

      // Day 0 was skipped because it is in the past; only days 1..4 (4 days) are scheduled
      expect(scheduledNotifTimes.length, equals(4));
      expect(scheduledNotifTimes.every((t) => t.isAfter(simulatedNow)), isTrue);

      // Config updated
      final config = await configRepo.getConfig(PrayerId.fajr);
      expect(config.alarmType, equals(PrayerAlarmType.notification));
    });

    // -------------------------------------------------------------------------
    // TEST-C-08: Active Ringing dismissal on Alarm -> Notification
    // -------------------------------------------------------------------------
    test('TEST-C-08: Active Ringing is immediately halted on Alarm -> Notification toggle', () async {
      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.asr,
        targetMode: PrayerAlarmType.notification,
        activeAlarmId: 26111020,
        isRinging: true,
      );

      expect(result.isSuccess, isTrue);
      expect(stoppedAlarmIds, contains(26111020));
      expect(cancelledAlarmIds.length, equals(5));
      expect(scheduledNotifTimes.length, equals(5));
    });

    // -------------------------------------------------------------------------
    // TEST-C-09 & TEST-C-35: Imminent Alarm Window handling
    // -------------------------------------------------------------------------
    test('TEST-C-09 & TEST-C-35: Imminent Alarm window defers today and suppresses today FLN', () async {
      nextAlarmCancelStatus = EventCancellationStatus.deferredImminent;

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.maghrib,
        targetMode: PrayerAlarmType.notification,
        scheduledEpoch: fiveDayTimes.first,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isDeferred, isTrue);
      expect(result.isCompleted, isFalse);
      expect(result.protectedAlarmEpoch, equals(fiveDayTimes.first));

      // CRITICAL: Today's FLN is suppressed (only 4 future days scheduled!)
      expect(scheduledNotifTimes.length, equals(4));
      expect(scheduledNotifTimes, isNot(contains(fiveDayTimes.first)));

      // Transition record persisted in waitingForImminentAlarm state
      final record = await transitionDataSource.getRecord(PrayerId.maghrib);
      expect(record, isNotNull);
      expect(record!.status, equals(TransitionStatus.waitingForImminentAlarm));
      expect(record.targetMode, equals(PrayerAlarmType.notification));

      // Config remains alarm until post-protected interval completes
      final currentConfig = await configRepo.getConfig(PrayerId.maghrib);
      expect(currentConfig.alarmType, equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // TEST-C-10: Alarm -> Off (Active Ringing)
    // -------------------------------------------------------------------------
    test('TEST-C-10: Alarm -> Off stops ringing and decommissions all future alerts', () async {
      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.isha,
        targetMode: PrayerAlarmType.off,
        activeAlarmId: 26111040,
        isRinging: true,
      );

      expect(result.isSuccess, isTrue);
      expect(stoppedAlarmIds, contains(26111040));
      expect(cancelledAlarmIds.length, equals(5));
      expect(scheduledNotifTimes, isEmpty);
      expect(scheduledAlarmTimes, isEmpty);

      final config = await configRepo.getConfig(PrayerId.isha);
      expect(config.alarmType, equals(PrayerAlarmType.off));
    });

    // -------------------------------------------------------------------------
    // TEST-C-11: Notification -> Off
    // -------------------------------------------------------------------------
    test('TEST-C-11: Notification -> Off removes FLN alerts without touching alarms', () async {
      await configRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.notification),
      );

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.fajr,
        targetMode: PrayerAlarmType.off,
      );

      expect(result.isSuccess, isTrue);
      expect(cancelledNotifIds.length, equals(5));
      expect(scheduledAlarmTimes, isEmpty);

      final config = await configRepo.getConfig(PrayerId.fajr);
      expect(config.alarmType, equals(PrayerAlarmType.off));
    });

    // -------------------------------------------------------------------------
    // TEST-C-12: Notification -> Alarm
    // -------------------------------------------------------------------------
    test('TEST-C-12: Notification -> Alarm cancels FLN and schedules alarms across 5 days', () async {
      await configRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.dhuhr,
        targetMode: PrayerAlarmType.alarm,
      );

      expect(result.isSuccess, isTrue);
      expect(cancelledNotifIds.length, equals(5));
      expect(scheduledAlarmTimes.length, equals(5));

      final config = await configRepo.getConfig(PrayerId.dhuhr);
      expect(config.alarmType, equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // TEST-C-13: Off -> Notification
    // -------------------------------------------------------------------------
    test('TEST-C-13: Off -> Notification schedules FLN notifications across 5 days', () async {
      await configRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
      );

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.asr,
        targetMode: PrayerAlarmType.notification,
      );

      expect(result.isSuccess, isTrue);
      expect(scheduledNotifTimes.length, equals(5));

      final config = await configRepo.getConfig(PrayerId.asr);
      expect(config.alarmType, equals(PrayerAlarmType.notification));
    });

    // -------------------------------------------------------------------------
    // TEST-C-14: Off -> Alarm
    // -------------------------------------------------------------------------
    test('TEST-C-14: Off -> Alarm schedules full-screen alarms across 5 days', () async {
      await configRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.off),
      );

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.maghrib,
        targetMode: PrayerAlarmType.alarm,
      );

      expect(result.isSuccess, isTrue);
      expect(scheduledAlarmTimes.length, equals(5));

      final config = await configRepo.getConfig(PrayerId.maghrib);
      expect(config.alarmType, equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // TEST-C-16: Scheduling failure marks record failed without blind rollback
    // -------------------------------------------------------------------------
    test('TEST-C-16: Failure during transition records failed status for UI retry', () async {
      shouldThrowOnSchedule = true;

      final coordinator = createCoordinator();
      final result = await coordinator.executeTransition(
        prayerId: PrayerId.isha,
        targetMode: PrayerAlarmType.notification,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('FLN scheduling error'));

      // Transition record preserved in failed state
      final record = await transitionDataSource.getRecord(PrayerId.isha);
      expect(record, isNotNull);
      expect(record!.status, equals(TransitionStatus.failed));
      expect(record.failureReason, contains('FLN scheduling error'));

      // Config was NOT blindly rolled back or modified
      final config = await configRepo.getConfig(PrayerId.isha);
      expect(config.alarmType, equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // TEST-C-17: Process death recovery resumes pending transition
    // -------------------------------------------------------------------------
    test('TEST-C-17: Startup recovery resumes interrupted pending transition', () async {
      // Simulate crash: record saved as pending, app restarts
      final unrecoveredRecord = PrayerAlertTransitionRecord(
        revision: 1,
        operationId: 'fajr_interrupted_op',
        prayerId: PrayerId.fajr,
        sourceMode: PrayerAlarmType.alarm,
        targetMode: PrayerAlarmType.notification,
        requestedAt: simulatedNow.subtract(const Duration(minutes: 5)),
        status: TransitionStatus.pending,
      );
      await transitionDataSource.saveRecord(unrecoveredRecord);

      final coordinator = createCoordinator();
      await coordinator.recoverIncompleteTransitions();

      // Successfully resumed and completed
      final config = await configRepo.getConfig(PrayerId.fajr);
      expect(config.alarmType, equals(PrayerAlarmType.notification));

      final record = await transitionDataSource.getRecord(PrayerId.fajr);
      expect(record, isNull);
    });

    // -------------------------------------------------------------------------
    // TEST-C-19 & TEST-C-40: Imminent recovery after protected interval elapsed
    // -------------------------------------------------------------------------
    test('TEST-C-19 & TEST-C-40: Imminent recovery finalizes after epoch + 60s without assuming fired', () async {
      final protectedEpoch = DateTime(2026, 11, 10, 12, 15, 0);

      // Record is in waitingForImminentAlarm
      final imminentRecord = PrayerAlertTransitionRecord(
        revision: 1,
        operationId: 'dhuhr_imminent_op',
        prayerId: PrayerId.dhuhr,
        sourceMode: PrayerAlarmType.alarm,
        targetMode: PrayerAlarmType.notification,
        requestedAt: simulatedNow,
        protectedAlarmEpoch: protectedEpoch,
        status: TransitionStatus.waitingForImminentAlarm,
      );
      await transitionDataSource.saveRecord(imminentRecord);

      // Advance time beyond epoch + 60s
      simulatedNow = protectedEpoch.add(const Duration(seconds: 65));

      final coordinator = createCoordinator();
      await coordinator.recoverIncompleteTransitions();

      // Post-protected cleanup ran: cancelAlarmSafely called, target reconciled
      expect(cancelledAlarmIds, contains(26111010));
      // Day 0 was in the past (protectedEpoch < simulatedNow), so only remaining 4 future days are scheduled
      expect(scheduledNotifTimes.length, equals(4));

      final config = await configRepo.getConfig(PrayerId.dhuhr);
      expect(config.alarmType, equals(PrayerAlarmType.notification));

      final record = await transitionDataSource.getRecord(PrayerId.dhuhr);
      expect(record, isNull);
    });

    // -------------------------------------------------------------------------
    // TEST-C-38: Concurrent opposite transitions serialized via per-prayer mutex
    // -------------------------------------------------------------------------
    test('TEST-C-38: Rapid concurrent taps on same prayer are serialized safely', () async {
      final coordinator = createCoordinator();

      // Rapidly launch Alarm -> Notification, then Notification -> Alarm
      final future1 = coordinator.executeTransition(
        prayerId: PrayerId.asr,
        targetMode: PrayerAlarmType.notification,
      );
      final future2 = coordinator.executeTransition(
        prayerId: PrayerId.asr,
        targetMode: PrayerAlarmType.alarm,
      );

      final results = await Future.wait([future1, future2]);
      expect(results[0].isSuccess, isTrue);
      expect(results[1].isSuccess, isTrue);

      // Final config must be the winner (future2: Alarm)
      final config = await configRepo.getConfig(PrayerId.asr);
      expect(config.alarmType, equals(PrayerAlarmType.alarm));
    });

    // -------------------------------------------------------------------------
    // EVIDENCE SUPPLEMENT: Imminent Guard Boundary Matrix (Requested by Review)
    // -------------------------------------------------------------------------
    group('P4.1-C Evidence Supplement: Imminent Guard Boundary Matrix', () {
      final repo = NotificationRepositoryImpl();
      final epoch = DateTime(2026, 11, 10, 12, 0, 0); // 12:00:00

      test('Boundary Point 1: epoch - 16s is OUTSIDE protection window', () {
        final t = epoch.subtract(const Duration(seconds: 16)); // 11:59:44
        expect(repo.isWithinImminentWindow(epoch, t), isFalse);
      });

      test('Boundary Point 2: epoch - 15s is INSIDE protection window', () {
        final t = epoch.subtract(const Duration(seconds: 15)); // 11:59:45
        expect(repo.isWithinImminentWindow(epoch, t), isTrue);
      });

      test('Boundary Point 3: epoch is INSIDE protection window', () {
        final t = epoch; // 12:00:00
        expect(repo.isWithinImminentWindow(epoch, t), isTrue);
      });

      test('Boundary Point 4: epoch + 30s is INSIDE protection window', () {
        final t = epoch.add(const Duration(seconds: 30)); // 12:00:30
        expect(repo.isWithinImminentWindow(epoch, t), isTrue);
      });

      test('Boundary Point 5: epoch + 60s is INSIDE protection window', () {
        final t = epoch.add(const Duration(seconds: 60)); // 12:01:00
        expect(repo.isWithinImminentWindow(epoch, t), isTrue);
      });

      test('Boundary Point 6: epoch + 61s is OUTSIDE protection window', () {
        final t = epoch.add(const Duration(seconds: 61)); // 12:01:01
        expect(repo.isWithinImminentWindow(epoch, t), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // EVIDENCE SUPPLEMENT: Crash Recovery 3-Tier Proof (Requested by Review)
    // -------------------------------------------------------------------------
    group('P4.1-C Evidence Supplement: Crash Recovery 3-Tier Proof', () {
      test('Tier 1: Recovery of pending transition interrupted before config commit', () async {
        final record = PrayerAlertTransitionRecord(
          revision: 1,
          operationId: 'fajr_crash_before_commit',
          prayerId: PrayerId.fajr,
          sourceMode: PrayerAlarmType.alarm,
          targetMode: PrayerAlarmType.notification,
          requestedAt: simulatedNow.subtract(const Duration(minutes: 2)),
          status: TransitionStatus.pending,
        );
        await transitionDataSource.saveRecord(record);

        final coordinator = createCoordinator();
        await coordinator.recoverIncompleteTransitions();

        // Target config committed
        final config = await configRepo.getConfig(PrayerId.fajr);
        expect(config.alarmType, equals(PrayerAlarmType.notification));

        // Purged from active transition storage
        final remaining = await transitionDataSource.getRecord(PrayerId.fajr);
        expect(remaining, isNull);
      });

      test('Tier 2: Recovery of interrupted transition mid-flight during reconciliation', () async {
        final record = PrayerAlertTransitionRecord(
          revision: 2,
          operationId: 'dhuhr_crash_during_reconciliation',
          prayerId: PrayerId.dhuhr,
          sourceMode: PrayerAlarmType.alarm,
          targetMode: PrayerAlarmType.off,
          requestedAt: simulatedNow.subtract(const Duration(minutes: 1)),
          status: TransitionStatus.reconciling,
        );
        await transitionDataSource.saveRecord(record);

        final coordinator = createCoordinator();
        await coordinator.recoverIncompleteTransitions();

        // Resumed and committed target mode (Off)
        final config = await configRepo.getConfig(PrayerId.dhuhr);
        expect(config.alarmType, equals(PrayerAlarmType.off));
        expect(cancelledAlarmIds, contains(26111010));

        final remaining = await transitionDataSource.getRecord(PrayerId.dhuhr);
        expect(remaining, isNull);
      });

      test('Tier 3: Recovery of transition inside imminent window when app was dead past epoch + 60s', () async {
        final protectedEpoch = DateTime(2026, 11, 10, 15, 30, 0);

        final record = PrayerAlertTransitionRecord(
          revision: 1,
          operationId: 'asr_crash_during_imminent',
          prayerId: PrayerId.asr,
          sourceMode: PrayerAlarmType.alarm,
          targetMode: PrayerAlarmType.notification,
          requestedAt: protectedEpoch.subtract(const Duration(seconds: 10)),
          protectedAlarmEpoch: protectedEpoch,
          status: TransitionStatus.waitingForImminentAlarm,
        );
        await transitionDataSource.saveRecord(record);

        // App reboots 5 minutes later (well after protected window elapsed)
        simulatedNow = protectedEpoch.add(const Duration(minutes: 5));

        final coordinator = createCoordinator();
        await coordinator.recoverIncompleteTransitions();

        // Step 1: cancelAlarmSafely called on lingering alarm (truthful cleanup, not assumed)
        expect(cancelledAlarmIds, contains(26111020));

        // Step 2: Target mode committed to config
        final config = await configRepo.getConfig(PrayerId.asr);
        expect(config.alarmType, equals(PrayerAlarmType.notification));

        // Step 3: Record deleted
        final remaining = await transitionDataSource.getRecord(PrayerId.asr);
        expect(remaining, isNull);
      });
    });
  });
}

