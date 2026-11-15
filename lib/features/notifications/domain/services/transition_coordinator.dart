import 'dart:async';
import 'dart:developer';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alert_transition_record.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';

/// Result returned after executing or attempting a transition.
class TransitionResult {
  final PrayerId prayerId;
  final PrayerAlarmType sourceMode;
  final PrayerAlarmType targetMode;
  final bool isCompleted;
  final bool isDeferred;
  final DateTime? protectedAlarmEpoch;
  final String? errorMessage;

  const TransitionResult({
    required this.prayerId,
    required this.sourceMode,
    required this.targetMode,
    required this.isCompleted,
    required this.isDeferred,
    this.protectedAlarmEpoch,
    this.errorMessage,
  });

  bool get isSuccess => isCompleted || isDeferred;
}

/// Typed delegate signatures for testable scheduling adapters.
typedef CancelAlarmAdapter = Future<EventCancellationStatus> Function(
  int id, {
  DateTime? expectedScheduledTime,
  String? expectedAssetAudioPath,
});
typedef StopActiveAlarmAdapter = Future<void> Function(int id);
typedef CancelNotificationAdapter = Future<EventCancellationStatus> Function(int id);
typedef ScheduleAlarmAdapter = Future<void> Function(
  PrayerId prayerId,
  DateTime dateTime,
  AudioSourceConfig audioSource,
  double? volume,
  bool enableVibration,
);
typedef ScheduleNotificationAdapter = Future<void> Function(
  PrayerId prayerId,
  DateTime dateTime,
);
typedef GetPrayerTimesForHorizonAdapter = Future<List<DateTime>> Function(PrayerId prayerId);
typedef NowProvider = DateTime Function();

/// Coordinates state transitions between alarm, notification, and off modes
/// with per-prayer serialization, crash recovery, and canonical imminent protection.
class TransitionCoordinator {
  final BasePrayerAlarmConfigRepository configRepository;
  final BasePrayerAlertTransitionLocalDataSource transitionDataSource;

  final CancelAlarmAdapter cancelAlarmSafely;
  final StopActiveAlarmAdapter stopActiveAlarm;
  final CancelNotificationAdapter cancelNotificationSafely;
  final ScheduleAlarmAdapter scheduleAlarm;
  final ScheduleNotificationAdapter scheduleNotification;
  final GetPrayerTimesForHorizonAdapter getPrayerTimesForHorizon;
  final NowProvider nowProvider;

  // Per-prayer async lock
  final Map<PrayerId, Future<void>> _locks = {};

  // Monotonic per-prayer revision counter
  final Map<PrayerId, int> _revisions = {};

  // Active timers for imminent cleanup
  final Map<PrayerId, Timer> _imminentTimers = {};

  TransitionCoordinator({
    required this.configRepository,
    required this.transitionDataSource,
    required this.cancelAlarmSafely,
    required this.stopActiveAlarm,
    required this.cancelNotificationSafely,
    required this.scheduleAlarm,
    required this.scheduleNotification,
    required this.getPrayerTimesForHorizon,
    NowProvider? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Executes a mode transition for a prayer with per-prayer mutex serialization.
  Future<TransitionResult> executeTransition({
    required PrayerId prayerId,
    required PrayerAlarmType targetMode,
    DateTime? scheduledEpoch,
    int? activeAlarmId,
    bool isRinging = false,
  }) async {
    // Acquire per-prayer mutex
    while (_locks[prayerId] != null) {
      await _locks[prayerId];
    }

    final completer = Completer<void>();
    _locks[prayerId] = completer.future;

    try {
      return await _executeTransitionInternal(
        prayerId: prayerId,
        targetMode: targetMode,
        scheduledEpoch: scheduledEpoch,
        activeAlarmId: activeAlarmId,
        isRinging: isRinging,
      );
    } finally {
      _locks.remove(prayerId);
      completer.complete();
    }
  }

  Future<TransitionResult> _executeTransitionInternal({
    required PrayerId prayerId,
    required PrayerAlarmType targetMode,
    DateTime? scheduledEpoch,
    int? activeAlarmId,
    bool isRinging = false,
  }) async {
    final now = nowProvider();
    final revision = (_revisions[prayerId] ?? 0) + 1;
    _revisions[prayerId] = revision;
    final operationId = '${prayerId.key}_${now.millisecondsSinceEpoch}_rev$revision';

    // 1. Read current config
    final currentConfig = await configRepository.getConfig(prayerId);
    final sourceMode = currentConfig.alarmType;

    // Check if transition is a true no-op
    final existingRecord = await transitionDataSource.getRecord(prayerId);
    if (sourceMode == targetMode &&
        (existingRecord == null || existingRecord.status == TransitionStatus.completed)) {
      return TransitionResult(
        prayerId: prayerId,
        sourceMode: sourceMode,
        targetMode: targetMode,
        isCompleted: true,
        isDeferred: false,
      );
    }

    // 2. Persist initial transition record (Source of Truth for in-flight operation)
    var transitionRecord = PrayerAlertTransitionRecord(
      revision: revision,
      operationId: operationId,
      prayerId: prayerId,
      sourceMode: sourceMode,
      targetMode: targetMode,
      requestedAt: now,
      status: TransitionStatus.pending,
    );
    await transitionDataSource.saveRecord(transitionRecord);

    try {
      // 3. Handle Active Ringing: dismiss audio immediately if moving away from Alarm mode
      if ((isRinging || activeAlarmId != null) &&
          sourceMode == PrayerAlarmType.alarm &&
          targetMode != PrayerAlarmType.alarm) {
        if (activeAlarmId != null) {
          log("🔔 Stopping actively ringing alarm $activeAlarmId for ${prayerId.key}");
          await stopActiveAlarm(activeAlarmId);
        }
      }

      // 4. Fetch the 5-day horizon prayer times
      final horizonTimes = await getPrayerTimesForHorizon(prayerId);
      final DateTime? todayEpoch = horizonTimes.isNotEmpty ? horizonTimes.first : scheduledEpoch;

      // 5. Evaluate today's alarm cancellation safety if transitioning FROM Alarm mode
      bool isDeferred = false;
      bool alreadyCancelledTodayAlarm = false;
      DateTime? protectedAlarmEpoch;

      if (sourceMode == PrayerAlarmType.alarm && targetMode != PrayerAlarmType.alarm && todayEpoch != null) {
        // Attempt safe cancellation of today's alarm
        final cancelStatus = await cancelAlarmSafely(
          _deriveAlarmId(prayerId, todayEpoch),
          expectedScheduledTime: todayEpoch,
        );

        if (cancelStatus == EventCancellationStatus.deferredImminent) {
          isDeferred = true;
          protectedAlarmEpoch = todayEpoch;
          log("⚠️ [TransitionCoordinator] Alarm for ${prayerId.key} at $todayEpoch is deferredImminent [-15s, +60s]");
        } else {
          alreadyCancelledTodayAlarm = true;
        }
      }

      // 6. Update record to reconciling or waitingForImminentAlarm
      if (isDeferred) {
        transitionRecord = transitionRecord.copyWith(
          status: TransitionStatus.waitingForImminentAlarm,
          protectedAlarmEpoch: protectedAlarmEpoch,
        );
        await transitionDataSource.saveRecord(transitionRecord);

        // Schedule Days 2..5 in target mode, suppressing today's FLN notification
        await _reconcileHorizonDays(
          prayerId: prayerId,
          targetMode: targetMode,
          horizonTimes: horizonTimes,
          skipDayZero: true, // Suppress today's notification to avoid double delivery
          config: currentConfig,
        );

        // Arm timer for post-protected interval cleanup
        _armPostProtectedTimer(prayerId, protectedAlarmEpoch!, revision, operationId);

        return TransitionResult(
          prayerId: prayerId,
          sourceMode: sourceMode,
          targetMode: targetMode,
          isCompleted: false,
          isDeferred: true,
          protectedAlarmEpoch: protectedAlarmEpoch,
        );
      } else {
        // Non-deferred transition: reconcile full 5-day horizon
        transitionRecord = transitionRecord.copyWith(status: TransitionStatus.reconciling);
        await transitionDataSource.saveRecord(transitionRecord);

        await _reconcileHorizonDays(
          prayerId: prayerId,
          targetMode: targetMode,
          horizonTimes: horizonTimes,
          skipDayZero: false,
          config: currentConfig,
          alreadyCancelledTodayAlarm: alreadyCancelledTodayAlarm,
        );

        // 7. Verify stale operation before committing config
        if (!_isOperationCurrent(prayerId, revision, operationId)) {
          log("🛑 Transition operation $operationId superseded by newer revision. Terminating without committing config.");
          return TransitionResult(
            prayerId: prayerId,
            sourceMode: sourceMode,
            targetMode: targetMode,
            isCompleted: false,
            isDeferred: false,
            errorMessage: 'Superseded by newer operation',
          );
        }

        // Commit target configuration to persistent storage
        final updatedConfig = currentConfig.copyWith(alarmType: targetMode);
        await configRepository.saveConfig(updatedConfig);

        // Transition successfully completed: delete transition record
        await transitionDataSource.deleteRecord(prayerId);

        return TransitionResult(
          prayerId: prayerId,
          sourceMode: sourceMode,
          targetMode: targetMode,
          isCompleted: true,
          isDeferred: false,
        );
      }
    } catch (e, stack) {
      log("❌ [TransitionCoordinator] Transition failed for ${prayerId.key}: $e\n$stack");
      // Record failure without rolling back config
      final failedRecord = transitionRecord.copyWith(
        status: TransitionStatus.failed,
        failureReason: e.toString(),
      );
      await transitionDataSource.saveRecord(failedRecord);

      return TransitionResult(
        prayerId: prayerId,
        sourceMode: sourceMode,
        targetMode: targetMode,
        isCompleted: false,
        isDeferred: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reconciles alarms and notifications across the 5-day horizon.
  Future<void> _reconcileHorizonDays({
    required PrayerId prayerId,
    required PrayerAlarmType targetMode,
    required List<DateTime> horizonTimes,
    required bool skipDayZero,
    required PrayerAlarmConfig config,
    bool alreadyCancelledTodayAlarm = false,
  }) async {
    for (int i = 0; i < horizonTimes.length; i++) {
      if (i == 0 && skipDayZero) {
        continue;
      }
      final date = horizonTimes[i];
      final alarmId = _deriveAlarmId(prayerId, date);
      final notifId = _deriveNotificationId(prayerId, date);
      final isPast = date.isBefore(nowProvider());

      switch (targetMode) {
        case PrayerAlarmType.alarm:
          // Decommission FLN notification
          await cancelNotificationSafely(notifId);
          // Schedule Alarm only if date is in the future
          if (!isPast) {
            await scheduleAlarm(
              prayerId,
              date,
              config.audioSource,
              config.volume,
              config.isVibrationEnabled ?? true,
            );
          }
          break;

        case PrayerAlarmType.notification:
          // Decommission Alarm (skip today if already cancelled in step 5)
          if (i > 0 || !alreadyCancelledTodayAlarm) {
            await cancelAlarmSafely(alarmId, expectedScheduledTime: date);
          }
          // Schedule FLN only if date is in the future
          if (!isPast) {
            await scheduleNotification(prayerId, date);
          }
          break;

        case PrayerAlarmType.off:
          // Decommission both (skip today if already cancelled in step 5)
          if (i > 0 || !alreadyCancelledTodayAlarm) {
            await cancelAlarmSafely(alarmId, expectedScheduledTime: date);
          }
          await cancelNotificationSafely(notifId);
          break;
      }
    }
  }

  /// Arms a timer to execute post-protected cleanup after now > protectedAlarmEpoch + 60s.
  void _armPostProtectedTimer(
    PrayerId prayerId,
    DateTime protectedAlarmEpoch,
    int revision,
    String operationId,
  ) {
    _imminentTimers[prayerId]?.cancel();

    final expirationTime = protectedAlarmEpoch.add(const Duration(seconds: 61));
    final durationRemaining = expirationTime.difference(nowProvider());
    final delay = durationRemaining.isNegative ? Duration.zero : durationRemaining;

    _imminentTimers[prayerId] = Timer(delay, () async {
      await _executePostProtectedCleanup(prayerId, protectedAlarmEpoch, revision, operationId);
    });
  }

  /// Performs post-protected interval verification and finalization.
  Future<void> _executePostProtectedCleanup(
    PrayerId prayerId,
    DateTime protectedAlarmEpoch,
    int revision,
    String operationId,
  ) async {
    while (_locks[prayerId] != null) {
      await _locks[prayerId];
    }
    final completer = Completer<void>();
    _locks[prayerId] = completer.future;

    try {
      if (!_isOperationCurrent(prayerId, revision, operationId)) {
        return;
      }

      final record = await transitionDataSource.getRecord(prayerId);
      if (record == null || record.status != TransitionStatus.waitingForImminentAlarm) {
        return;
      }

      log("🧹 [TransitionCoordinator] Executing truthful post-protected cleanup for ${prayerId.key}");

      // Step 1: Run cancelAlarmSafely to verify lingering state
      final alarmId = _deriveAlarmId(prayerId, protectedAlarmEpoch);
      await cancelAlarmSafely(alarmId, expectedScheduledTime: protectedAlarmEpoch);

      // Step 2: Reconcile target subsystem across active horizon
      final horizonTimes = await getPrayerTimesForHorizon(prayerId);
      final currentConfig = await configRepository.getConfig(prayerId);

      await _reconcileHorizonDays(
        prayerId: prayerId,
        targetMode: record.targetMode,
        horizonTimes: horizonTimes,
        skipDayZero: false,
        config: currentConfig,
      );

      // Step 3: Update config and delete transition record
      final updatedConfig = currentConfig.copyWith(alarmType: record.targetMode);
      await configRepository.saveConfig(updatedConfig);
      await transitionDataSource.deleteRecord(prayerId);

      log("✅ [TransitionCoordinator] Post-protected transition completed for ${prayerId.key} -> ${record.targetMode.key}");
    } catch (e, stack) {
      log("❌ [TransitionCoordinator] Post-protected cleanup failed: $e\n$stack");
    } finally {
      _locks.remove(prayerId);
      completer.complete();
    }
  }

  /// Recovers incomplete transitions upon application launch.
  Future<void> recoverIncompleteTransitions() async {
    final records = await transitionDataSource.getAllRecords();
    final now = nowProvider();

    for (final entry in records.entries) {
      final prayerId = entry.key;
      final record = entry.value;

      switch (record.status) {
        case TransitionStatus.waitingForImminentAlarm:
          if (record.protectedAlarmEpoch != null) {
            _revisions[prayerId] = record.revision;
            final expiredThreshold = record.protectedAlarmEpoch!.add(const Duration(seconds: 60));
            if (now.isAfter(expiredThreshold)) {
              log("🔄 [TransitionCoordinator] Recovering expired imminent transition for ${prayerId.key}");
              await _executePostProtectedCleanup(
                prayerId,
                record.protectedAlarmEpoch!,
                record.revision,
                record.operationId,
              );
            } else {
              log("⏳ [TransitionCoordinator] Re-arming recovery timer for pending imminent alarm: ${prayerId.key}");
              _armPostProtectedTimer(
                prayerId,
                record.protectedAlarmEpoch!,
                record.revision,
                record.operationId,
              );
            }
          }
          break;

        case TransitionStatus.pending:
        case TransitionStatus.reconciling:
          log("🔄 [TransitionCoordinator] Resuming interrupted transition for ${prayerId.key} -> ${record.targetMode.key}");
          await executeTransition(
            prayerId: prayerId,
            targetMode: record.targetMode,
          );
          break;

        case TransitionStatus.failed:
          // Leave intact so UI surfaces retry
          log("⚠️ [TransitionCoordinator] Preserving failed transition record for ${prayerId.key} (retryable)");
          break;

        case TransitionStatus.completed:
          await transitionDataSource.deleteRecord(prayerId);
          break;
      }
    }
  }

  bool _isOperationCurrent(PrayerId prayerId, int revision, String operationId) {
    final current = _revisions[prayerId];
    return current == null || current == revision;
  }

  int _deriveAlarmId(PrayerId prayerId, DateTime date) {
    final year = date.year % 100;
    final month = date.month;
    final day = date.day;
    final prayerIdx = prayerId.index;
    return (year * 1000000) + (month * 10000) + (day * 100) + (prayerIdx * 10) + 0;
  }

  int _deriveNotificationId(PrayerId prayerId, DateTime date) {
    final year = date.year % 100;
    final month = date.month;
    final day = date.day;
    final prayerIdx = prayerId.index;
    return (year * 1000000) + (month * 10000) + (day * 100) + (prayerIdx * 10) + 1;
  }

  void dispose() {
    for (final timer in _imminentTimers.values) {
      timer.cancel();
    }
    _imminentTimers.clear();
  }
}

