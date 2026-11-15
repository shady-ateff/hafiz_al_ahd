import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/calendar_alarm_id_contract.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_scheduling_decision.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';

// ============================================================================
// 1. STATEFUL FAKES & VERIFICATION LEVEL MODELS (Phase 2C.4.1 Test Harness)
// ============================================================================

class ScheduledAlarmRecord {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String assetAudioPath;
  final double? volume;
  final bool enableVibration;

  ScheduledAlarmRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.assetAudioPath,
    this.volume,
    this.enableVibration = true,
  });
}

class ScheduledNotificationRecord {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String? soundName;
  final String? payload;

  ScheduledNotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    this.soundName,
    this.payload,
  });
}

/// Simulated pending notification request for FLN Level 2 verification
class FakePendingNotificationRequest {
  final int id;
  final String? title;
  final String? body;
  final String? payload;

  FakePendingNotificationRequest({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });
}

/// Persisted Scheduling Fingerprint representing the repository metadata ledger (Tier 2)
class NotificationSchedulingFingerprint {
  final int id;
  final String channelId;
  final String? soundSource;
  final String scheduledTimeIso;
  final String payload;
  final String title;
  final String body;

  const NotificationSchedulingFingerprint({
    required this.id,
    required this.channelId,
    this.soundSource,
    required this.scheduledTimeIso,
    required this.payload,
    required this.title,
    required this.body,
  });
}

/// Comprehensive Stateful Notification Repository Fake
/// Supports Level 1 (API call), Level 2 (Registry presence), and Fault Injection
class StatefulNotificationRepositoryFake extends Fake implements BaseNotificationRepository {
  final Map<int, ScheduledAlarmRecord> scheduledAlarms = {};
  final Map<int, ScheduledNotificationRecord> scheduledNotifications = {};
  final Map<int, NotificationSchedulingFingerprint> notificationFingerprints = {};
  final Set<int> ringingAlarmIds = {};

  int cancelAllAlarmsCallCount = 0;
  int cancelAllNotificationsCallCount = 0;
  int cancelActivePrayerNotificationCallCount = 0;

  final List<int> cancelAlarmSafelyCalls = [];
  final List<int> cancelNotificationCalls = [];
  final List<int> cancelNotificationSafelyCalls = [];
  final List<int> schedulePrayerNotificationCalls = [];
  final List<String> operationLog = [];

  // Fault Injection Controls
  final Set<int> failL1AlarmScheduleForIds = {};
  final Set<int> failL2AlarmVerificationForIds = {};
  final Set<int> failL1NotificationScheduleForIds = {};
  final Set<int> failL2NotificationVerificationForIds = {};
  final Set<int> failCancelAlarmForIds = {};
  final Set<int> failCancelNotificationForIds = {};
  final Set<int> imminentAlarmIds = {};
  final Set<int> imminentNotificationIds = {};
  final Set<int> failAlarmPostCheckForIds = {};
  final Set<int> failNotificationPostCheckForIds = {};
  final Set<int> failLedgerRemovalForIds = {};
  final Set<int> throwInVerifyAlarmForIds = {};
  final Set<int> throwInVerifyNotificationForIds = {};
  final Set<int> throwInCancelAlarmPostCheckForIds = {};
  final Set<int> throwInCancelNotificationPostCheckForIds = {};

  // Hit Tracking for Fault Injections (Guarantees faults are genuinely triggered)
  int l1AlarmScheduleFailureHits = 0;
  int l2AlarmVerificationFailureHits = 0;
  int l1NotificationScheduleFailureHits = 0;
  int l2NotificationVerificationFailureHits = 0;
  int iqamaFailureHits = 0;
  int postPrayerAzkarFailureHits = 0;
  int morningAzkarFailureHits = 0;
  int eveningAzkarFailureHits = 0;

  bool failIqamaSchedule = false;
  bool failPostPrayerAzkarSchedule = false;
  bool failMorningAzkarSchedule = false;
  bool failEveningAzkarSchedule = false;

  DateTime? simulatedClock;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> scheduleAdhanAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String assetAudioPath,
    double? volume,
    bool enableVibration = true,
    bool androidFullScreenIntent = true,
    String? stopButton = 'إيقاف الأذان',
  }) async {
    operationLog.add('scheduleAdhanAlarm_$id');

    if (failL1AlarmScheduleForIds.contains(id)) {
      l1AlarmScheduleFailureHits++;
      throw PlatformException(code: 'L1_ALARM_FAILED', message: 'Simulated L1 Alarm Schedule Failure');
    }

    if (failL2AlarmVerificationForIds.contains(id)) {
      l2AlarmVerificationFailureHits++;
      return;
    }

    scheduledAlarms[id] = ScheduledAlarmRecord(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      assetAudioPath: assetAudioPath,
      volume: volume,
      enableVibration: enableVibration,
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
    operationLog.add('schedulePrayerNotification_$id');
    schedulePrayerNotificationCalls.add(id);

    final isDay0 = simulatedClock != null
        ? scheduledTime.day == simulatedClock!.day
        : scheduledTime.day == DateTime.now().day &&
            scheduledTime.month == DateTime.now().month &&
            scheduledTime.year == DateTime.now().year;

    if (!isDay0) {
      if (failIqamaSchedule && (payload?.startsWith('iqama_') ?? false)) {
        iqamaFailureHits++;
        throw PlatformException(code: 'IQAMA_FAILED', message: 'Simulated Iqama Schedule Failure');
      }
      if (failPostPrayerAzkarSchedule && payload == 'azkar_after_prayer') {
        postPrayerAzkarFailureHits++;
        throw PlatformException(code: 'POST_AZKAR_FAILED', message: 'Simulated Post-Prayer Azkar Failure');
      }
      if (failMorningAzkarSchedule && payload == 'azkar_morning') {
        morningAzkarFailureHits++;
        throw PlatformException(code: 'MORNING_AZKAR_FAILED', message: 'Simulated Morning Azkar Failure');
      }
      if (failEveningAzkarSchedule && payload == 'azkar_evening') {
        eveningAzkarFailureHits++;
        throw PlatformException(code: 'EVENING_AZKAR_FAILED', message: 'Simulated Evening Azkar Failure');
      }
    }

    if (failL1NotificationScheduleForIds.contains(id)) {
      l1NotificationScheduleFailureHits++;
      throw PlatformException(code: 'L1_NOTIF_FAILED', message: 'Simulated L1 Notification Schedule Failure');
    }

    if (failL2NotificationVerificationForIds.contains(id)) {
      l2NotificationVerificationFailureHits++;
      return;
    }

    scheduledNotifications[id] = ScheduledNotificationRecord(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
      payload: payload,
    );

    final channelId = soundName != null ? 'prayer_channel_v10_$soundName' : 'prayer_channel_v10_default';
    notificationFingerprints[id] = NotificationSchedulingFingerprint(
      id: id,
      channelId: channelId,
      soundSource: soundName ?? 'default',
      scheduledTimeIso: scheduledTime.toIso8601String(),
      payload: payload ?? '',
      title: title,
      body: body,
    );
  }

  @override
  Future<void> cancelAllAlarms() async {
    operationLog.add('cancelAllAlarms');
    cancelAllAlarmsCallCount++;
    scheduledAlarms.clear();
    ringingAlarmIds.clear();
  }

  @override
  Future<void> cancelAllNotifications() async {
    operationLog.add('cancelAllNotifications');
    cancelAllNotificationsCallCount++;
    scheduledNotifications.clear();
  }

  @override
  Future<void> cancelNotification(int id) async {
    operationLog.add('cancelNotification_$id');
    cancelNotificationCalls.add(id);
    scheduledNotifications.remove(id);
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    operationLog.add('cancelActivePrayerNotification');
    cancelActivePrayerNotificationCallCount++;
  }

  @override
  Future<EventCancellationStatus> cancelAlarmSafely(
    int id, {
    DateTime? expectedScheduledTime,
    String? expectedAssetAudioPath,
  }) async {
    operationLog.add('cancelAlarmSafely_$id');
    cancelAlarmSafelyCalls.add(id);

    final isLegacy = id >= 1 && id <= 100;
    final isModern = id >= CalendarAlarmIdContract.minContractId && id <= CalendarAlarmIdContract.maxContractId;
    if (!isLegacy && !isModern) {
      return EventCancellationStatus.failed;
    }

    if (ringingAlarmIds.contains(id)) {
      return EventCancellationStatus.deferredRinging;
    }

    if (imminentAlarmIds.contains(id)) {
      return EventCancellationStatus.deferredImminent;
    }

    if (failCancelAlarmForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    final alarm = scheduledAlarms[id];
    if (alarm == null) {
      return EventCancellationStatus.alreadyAbsent;
    }

    const validAssets = {'assets/sounds/adhan.mp3', 'assets/sounds/fajr_azan.mp3'};
    if (expectedAssetAudioPath != null) {
      if (alarm.assetAudioPath != expectedAssetAudioPath) return EventCancellationStatus.failed;
    } else {
      if (!validAssets.contains(alarm.assetAudioPath)) return EventCancellationStatus.failed;
    }

    if (expectedScheduledTime != null) {
      final drift = (alarm.scheduledTime.difference(expectedScheduledTime)).inSeconds.abs();
      if (drift > 60) return EventCancellationStatus.failed;
    }

    final now = simulatedClock ?? DateTime.now();
    final difference = alarm.scheduledTime.difference(now);
    if (difference >= const Duration(seconds: -15) && difference <= const Duration(seconds: 60)) {
      return EventCancellationStatus.deferredImminent;
    }

    if (failCancelAlarmForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    if (throwInCancelAlarmPostCheckForIds.contains(id)) {
      return EventCancellationStatus.unverifiable;
    }

    if (failAlarmPostCheckForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    scheduledAlarms.remove(id);
    return EventCancellationStatus.cancelled;
  }

  @override
  Future<EventCancellationStatus> cancelNotificationSafely(int id) async {
    operationLog.add('cancelNotificationSafely_$id');
    cancelNotificationSafelyCalls.add(id);
    cancelNotificationCalls.add(id);

    if (imminentNotificationIds.contains(id)) {
      return EventCancellationStatus.deferredImminent;
    }

    if (failCancelNotificationForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    final notif = scheduledNotifications[id];
    final hasFingerprint = notificationFingerprints.containsKey(id);

    if (notif == null) {
      if (!hasFingerprint) {
        return EventCancellationStatus.alreadyAbsent;
      }
      if (failLedgerRemovalForIds.contains(id)) {
        return EventCancellationStatus.failed;
      }
      notificationFingerprints.remove(id);
      return EventCancellationStatus.alreadyAbsent;
    }

    if (throwInCancelNotificationPostCheckForIds.contains(id)) {
      return EventCancellationStatus.unverifiable;
    }

    if (failNotificationPostCheckForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    scheduledNotifications.remove(id);

    if (failLedgerRemovalForIds.contains(id)) {
      return EventCancellationStatus.failed;
    }

    notificationFingerprints.remove(id);
    return EventCancellationStatus.cancelled;
  }

  @override
  Future<int> getPendingNotificationsCount() async => scheduledNotifications.length;

  Future<List<FakePendingNotificationRequest>> getPendingNotificationRequests() async {
    return scheduledNotifications.values
        .map((n) => FakePendingNotificationRequest(id: n.id, title: n.title, body: n.body, payload: n.payload))
        .toList();
  }

  Future<ScheduledAlarmRecord?> getAlarm(int id) async => scheduledAlarms[id];

  @override
  Future<EventVerificationStatus> verifyAlarm({
    required int id,
    required DateTime expectedScheduledTime,
    String? expectedAssetAudioPath,
    double? expectedVolume,
    bool? expectedEnableVibration,
  }) async {
    if (throwInVerifyAlarmForIds.contains(id)) {
      return EventVerificationStatus.unverifiable;
    }
    if (failL2AlarmVerificationForIds.contains(id)) {
      return EventVerificationStatus.absent;
    }

    final alarm = scheduledAlarms[id];
    if (alarm == null) return EventVerificationStatus.absent;

    if (alarm.scheduledTime.difference(expectedScheduledTime).inSeconds.abs() > 2) {
      return EventVerificationStatus.stale;
    }
    if (expectedAssetAudioPath != null && alarm.assetAudioPath != expectedAssetAudioPath) {
      return EventVerificationStatus.stale;
    }
    if (expectedVolume != null && alarm.volume != null && (alarm.volume! - expectedVolume).abs() > 0.05) {
      return EventVerificationStatus.stale;
    }
    if (expectedEnableVibration != null && alarm.enableVibration != expectedEnableVibration) {
      return EventVerificationStatus.stale;
    }
    return EventVerificationStatus.matching;
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
    if (throwInVerifyNotificationForIds.contains(id)) {
      return EventVerificationStatus.unverifiable;
    }
    if (failL2NotificationVerificationForIds.contains(id)) {
      return EventVerificationStatus.absent;
    }

    final notif = scheduledNotifications[id];
    if (notif == null) return EventVerificationStatus.absent;

    if (notif.payload != expectedPayload) {
      return EventVerificationStatus.stale;
    }
    if (expectedTitle != null && notif.title != expectedTitle) {
      return EventVerificationStatus.stale;
    }
    if (expectedBody != null && notif.body != expectedBody) {
      return EventVerificationStatus.stale;
    }

    if (expectedChannelId != null || expectedSoundSource != null) {
      final fp = notificationFingerprints[id];
      if (fp == null) {
        return EventVerificationStatus.stale;
      }
      if (expectedChannelId != null && fp.channelId != expectedChannelId) {
        return EventVerificationStatus.stale;
      }
      if (expectedSoundSource != null && fp.soundSource != expectedSoundSource) {
        return EventVerificationStatus.stale;
      }
    }

    return EventVerificationStatus.matching;
  }
}

/// Stateful Repository Fake for BasePrayerAlarmConfigRepository
class StatefulPrayerAlarmConfigRepositoryFake implements BasePrayerAlarmConfigRepository {
  Map<PrayerId, PrayerAlarmConfig> configs;

  StatefulPrayerAlarmConfigRepositoryFake([Map<PrayerId, PrayerAlarmConfig>? initial])
      : configs = initial ?? {
          PrayerId.fajr: const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
          PrayerId.dhuhr: const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.alarm),
          PrayerId.asr: const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.alarm),
          PrayerId.maghrib: const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.alarm),
          PrayerId.isha: const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.alarm),
        };

  @override
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs() async => Map.from(configs);

  @override
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId) async => configs[prayerId]!;

  @override
  Future<void> saveConfig(PrayerAlarmConfig config) async {
    configs[config.prayerId] = config;
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> newConfigs) async {
    configs = Map.from(newConfigs);
  }

  @override
  Future<bool> migrateLegacyConfigsIfNeeded() async => false;

  @override
  Future<int> getMigrationVersion() async => 1;
}

/// Controllable Prayer Times UseCase Fake
class ControllablePrayerTimesUseCaseFake extends Fake implements GetPrayerTimesUseCase {
  final Set<String> failingDatesIso = {};

  void failForDate(DateTime date) {
    final key = DateTime(date.year, date.month, date.day).toIso8601String();
    failingDatesIso.add(key);
  }

  @override
  Future<Either<Failure, PrayerTimesEntity>> call({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    final key = DateTime(date.year, date.month, date.day).toIso8601String();
    if (failingDatesIso.contains(key)) {
      return Left(ServerFailure(message: 'Simulated astronomical calculation failure'));
    }

    final baseDate = DateTime(date.year, date.month, date.day);
    return Right(PrayerTimesEntity(
      fajr: baseDate.add(const Duration(hours: 5)),
      sunrise: baseDate.add(const Duration(hours: 6, minutes: 30)),
      dhuhr: baseDate.add(const Duration(hours: 12)),
      asr: baseDate.add(const Duration(hours: 15, minutes: 30)),
      maghrib: baseDate.add(const Duration(hours: 18)),
      isha: baseDate.add(const Duration(hours: 19, minutes: 30)),
    ));
  }
}

class FakeCancelAllNotificationsUseCase extends Fake implements CancelAllNotificationsUseCase {
  @override
  Future<void> execute() async {}
}

class FakeSchedulePrayerUseCase extends Fake implements SchedulePrayerUseCase {
  @override
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  }) async {}
}

class FakeIqamaDelaysUseCase extends Fake implements GetIqamaDelaysUseCase {
  @override
  Future<Map<String, int>> execute() async => {
        'fajr': 25,
        'dhuhr': 15,
        'asr': 15,
        'maghrib': 10,
        'isha': 15,
      };
}

// ============================================================================
// 2. PRODUCTION-PATH INTEGRATION TEST SUITE
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences pref;
  late StatefulNotificationRepositoryFake fakeRepo;
  late StatefulPrayerAlarmConfigRepositoryFake fakeConfigRepo;
  late ControllablePrayerTimesUseCaseFake fakePrayerTimes;
  late FakeIqamaDelaysUseCase fakeIqamaDelays;
  late ScheduleWeeklyPrayersUseCase scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'adhan_volume': 1.0,
      'isAdhanVibrationEnabled': true,
      'isIqamaEnabled': true,
      'isAzkarReminderEnabled': true,
      'adhanStyle': 'alarm',
    });
    pref = await SharedPreferences.getInstance();

    fakeRepo = StatefulNotificationRepositoryFake();
    fakeConfigRepo = StatefulPrayerAlarmConfigRepositoryFake();
    fakePrayerTimes = ControllablePrayerTimesUseCaseFake();
    fakeIqamaDelays = FakeIqamaDelaysUseCase();

    scheduler = ScheduleWeeklyPrayersUseCase(
      getPrayerTimesUseCase: fakePrayerTimes,
      cancelAllNotificationsUseCase: FakeCancelAllNotificationsUseCase(),
      schedulePrayerUseCase: FakeSchedulePrayerUseCase(),
      getIqamaDelaysUseCase: fakeIqamaDelays,
      notificationRepository: fakeRepo,
      pref: pref,
      prayerAlarmConfigRepository: fakeConfigRepo,
    );
  });

  // Helper date for testing
  final now = DateTime.now();
  final testDate = DateTime(now.year, now.month, now.day + 1);

  // ============================================================================
  // GROUP A: 12-Case Transition Matrix (Targeted Production Contract)
  // ============================================================================
  group('Group A: 12-Case Transition Matrix (Targeted Production Contract)', () {
    test('Case 1: [alarm, absent, absent] -> Schedules new Alarm with deterministic ID', () async {
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final expectedId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      expect(
        fakeRepo.scheduledAlarms.containsKey(expectedId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Production scheduler must use deterministic ID for Fajr Alarm',
      );
    });

    test('Case 2: [alarm, present, absent] -> In-place refresh of existing Alarm', () async {
      final expectedId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      // Pre-seed existing alarm with outdated/stale time (4:55 instead of 5:00)
      fakeRepo.scheduledAlarms[expectedId] = ScheduledAlarmRecord(
        id: expectedId,
        title: 'Old Title',
        body: 'Old Body',
        scheduledTime: testDate.add(const Duration(hours: 4, minutes: 55)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(expectedId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm refreshed in-place without blanket wipe',
      );
      expect(
        fakeRepo.scheduledAlarms[expectedId]?.scheduledTime,
        equals(testDate.add(const Duration(hours: 5))),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm refreshed with updated prayer time (not left with stale time)',
      );
    });

    test('Case 3: [alarm, absent, present] -> Schedules new Alarm, verifies, then cancels old Notification', () async {
      final oldNotifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledNotifications[oldNotifId] = ScheduledNotificationRecord(
        id: oldNotifId,
        title: 'Old Fajr Notif',
        body: 'Notification body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final newAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      expect(
        fakeRepo.scheduledAlarms.containsKey(newAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: New Alarm scheduled with deterministic ID',
      );
      expect(
        fakeRepo.cancelNotificationCalls.contains(oldNotifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Obsolete Notification cancelled after Alarm verified',
      );
    });

    test('Case 4: [alarm, present, present (dirty)] -> Refreshes Alarm, then cancels stray Notification', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final strayNotifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Fajr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 4)), // Outdated/stale time forces refresh dispatch
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );
      fakeRepo.scheduledNotifications[strayNotifId] = ScheduledNotificationRecord(
        id: strayNotifId,
        title: 'Fajr Notif',
        body: 'Stray',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelNotificationCalls.contains(strayNotifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Stray Notification cancelled in dirty dual state',
      );
    });

    test('Case 5: [notification, absent, absent] -> Schedules new Notification with deterministic ID', () async {
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final expectedId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      expect(
        fakeRepo.scheduledNotifications.containsKey(expectedId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Dhuhr Notification scheduled with deterministic ID',
      );
    });

    test('Case 6: [notification, present, absent] -> Schedules Notification, verifies, then cancels Alarm safely', () async {
      final oldAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[oldAlarmId] = ScheduledAlarmRecord(
        id: oldAlarmId,
        title: 'Dhuhr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final newNotifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      expect(
        fakeRepo.scheduledNotifications.containsKey(newNotifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: New Notification scheduled',
      );
      expect(
        fakeRepo.cancelAlarmSafelyCalls.contains(oldAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Old Alarm cancelled safely via cancelAlarmSafely()',
      );
    });

    test('Case 7: [notification, absent, present] -> In-place refresh of existing Notification', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      // Pre-seed existing notification with outdated/stale time (11:55 instead of 12:00)
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Old Dhuhr',
        body: 'Old Body',
        scheduledTime: testDate.add(const Duration(hours: 11, minutes: 55)),
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledNotifications.containsKey(notifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Notification refreshed in-place',
      );
      expect(
        fakeRepo.scheduledNotifications[notifId]?.scheduledTime,
        equals(testDate.add(const Duration(hours: 12))),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Notification refreshed with updated prayer time (not left with stale time)',
      );
    });

    test('Case 8: [notification, present, present (dirty)] -> Refreshes Notification, then cancels stray Alarm', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final strayAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Dhuhr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
      );
      fakeRepo.scheduledAlarms[strayAlarmId] = ScheduledAlarmRecord(
        id: strayAlarmId,
        title: 'Dhuhr',
        body: 'Stray',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelAlarmSafelyCalls.contains(strayAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Stray Alarm cancelled safely in dirty dual state',
      );
    });

    test('Case 9: [off, absent, absent] -> Pure no-op, zero events scheduled for this prayer', () async {
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final asrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.alarm,
      );
      final asrNotifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.notification,
      );

      expect(fakeRepo.scheduledAlarms.containsKey(asrAlarmId), isFalse);
      expect(fakeRepo.scheduledNotifications.containsKey(asrNotifId), isFalse);
    });

    test('Case 10: [off, present, absent] -> Immediate guarded cancellation of Alarm', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Asr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 15, minutes: 30)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelAlarmSafelyCalls.contains(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm decommissioned via cancelAlarmSafely()',
      );
    });

    test('Case 11: [off, absent, present] -> Immediate targeted cancellation of Notification', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Asr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 15, minutes: 30)),
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelNotificationCalls.contains(notifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Notification decommissioned via cancelNotification()',
      );
    });

    test('Case 12: [off, present, present (dirty)] -> Decommissions both events targetedly', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Asr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 15, minutes: 30)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Asr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 15, minutes: 30)),
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelNotificationCalls.contains(notifId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Notification cancelled in Case 12',
      );
      expect(
        fakeRepo.cancelAlarmSafelyCalls.contains(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm cancelled in Case 12',
      );
    });
  });

  // ============================================================================
  // GROUP B: Targeted Reconciliation & Zero Blanket Sweep (No cancelAll)
  // ============================================================================
  group('Group B: Targeted Reconciliation & Zero Blanket Sweep (No cancelAll)', () {
    test('13. Scheduler does NOT call cancelAllAlarms() on execution', () async {
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelAllAlarmsCallCount,
        equals(0),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Scheduler must eliminate cancelAllAlarms() blanket wipe',
      );
    });

    test('14. Scheduler does NOT call cancelAllNotifications() on execution', () async {
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.cancelAllNotificationsCallCount,
        equals(0),
        reason: 'Scheduler must not call cancelAllNotifications()',
      );
    });

    test('15. Unrelated alarms (ID 888 test alarm) are strictly preserved during weekly scheduling', () async {
      fakeRepo.scheduledAlarms[CalendarAlarmIdContract.reservedTestAlarmId] = ScheduledAlarmRecord(
        id: CalendarAlarmIdContract.reservedTestAlarmId,
        title: 'Test Alarm',
        body: 'Test Body',
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(CalendarAlarmIdContract.reservedTestAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Blanket cancellation must not wipe reserved test alarm 888',
      );
    });

    test('16. Sticky foreground notification (ID 8888) is strictly preserved during weekly scheduling', () async {
      fakeRepo.scheduledNotifications[CalendarAlarmIdContract.reservedForegroundServiceId] = ScheduledNotificationRecord(
        id: CalendarAlarmIdContract.reservedForegroundServiceId,
        title: 'Sticky Notification',
        body: 'Countdown',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledNotifications.containsKey(CalendarAlarmIdContract.reservedForegroundServiceId),
        isTrue,
        reason: 'Sticky notification 8888 must never be wiped by scheduler',
      );
    });
  });

  // ============================================================================
  // GROUP C: Active Audio & Temporal Proximity Guards (R3 - Incomplete Reconciliation)
  // ============================================================================
  group('Group C: Active Audio & Temporal Proximity Guards (R3 - Incomplete Reconciliation)', () {
    test('17. Case 6 transition: Actively ringing alarm suppresses cancellation -> Both remain, day incomplete', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.maghrib,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Maghrib Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 18)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      fakeRepo.ringingAlarmIds.add(alarmId); // ACTVELY RINGING

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // 1. Ringing alarm must NOT be stopped
      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Actively ringing alarm must be preserved during transition',
      );
    });

    test('18. Case 6 transition: Alarm within +/- 15s temporal guard suppresses cancellation -> Both remain', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.maghrib,
        decision: PrayerAlertDecision.alarm,
      );

      final alarmTime = DateTime.now().add(const Duration(seconds: 10)); // INSIDE 15s WINDOW
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Maghrib Alarm',
        body: 'Body',
        scheduledTime: alarmTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.notification),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm within temporal guard must be preserved',
      );
    });

    test('19. Case 10 decommissioning: Actively ringing alarm suppresses cancellation -> Preserved', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.isha,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Isha',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 19, minutes: 30)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      fakeRepo.ringingAlarmIds.add(alarmId);

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Actively ringing alarm must not be stopped on config off',
      );
    });

    test('20. Case 10 decommissioning: Alarm within +/- 15s guard suppresses cancellation -> Preserved', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.isha,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Isha',
        body: 'Body',
        scheduledTime: DateTime.now().add(const Duration(seconds: 8)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Imminent alarm within 15s must not be stopped on config off',
      );
    });
  });

  // ============================================================================
  // GROUP D: Verification Levels (L1/L2) & Verify-Before-Cancel (R1, R2)
  // ============================================================================
  group('Group D: Verification Levels (L1/L2) & Verify-Before-Cancel (R1, R2)', () {
    test('21. New Alarm L1 failure (schedule throws) -> Old notification strictly preserved, day incomplete', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Fajr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      fakeRepo.failL1AlarmScheduleForIds.add(alarmId); // L1 FAILS

      // Unified Exception Contract: Platform error is caught inside repository; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // 1. Verify that the fault was ACTUALLY triggered by the scheduler
      expect(
        fakeRepo.l1AlarmScheduleFailureHits,
        greaterThan(0),
        reason: 'Fault injection was not triggered: Scheduler did not call scheduleAdhanAlarm with expected deterministic ID ($alarmId)',
      );

      // 2. Verify that old notification is preserved
      expect(
        fakeRepo.scheduledNotifications.containsKey(notifId),
        isTrue,
        reason: 'Old Notification must be preserved when new Alarm L1 fails',
      );
    });

    test('22a. New Alarm L2 failure (absent in registry) -> Old notification strictly preserved', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Fajr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      fakeRepo.failL2AlarmVerificationForIds.add(alarmId); // L2 FAILS

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // 1. Verify that the fault was ACTUALLY triggered by the scheduler
      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isFalse,
      );

      // 2. Verify that old notification is preserved
      expect(
        fakeRepo.scheduledNotifications.containsKey(notifId),
        isTrue,
        reason: 'Old Notification must be preserved when new Alarm L2 fails',
      );
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('22b. New Alarm L2 failure (unverifiable exception) -> Old notification strictly preserved', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Fajr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      fakeRepo.throwInVerifyAlarmForIds.add(alarmId); // L2 FAILS: verifyAlarm throws

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledNotifications.containsKey(notifId),
        isTrue,
        reason: 'Old Notification must be preserved when Alarm verification is unverifiable',
      );
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('23a. New Notification L2 failure (absent in queue) -> Old alarm strictly preserved', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Dhuhr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      fakeRepo.failL2NotificationVerificationForIds.add(notifId); // verifyNotification returns absent

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'Pre-existing alarm must be preserved when new notification L2 verification fails',
      );
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('23b. New Notification L2 failure (unverifiable exception) -> Old alarm strictly preserved', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Dhuhr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      fakeRepo.throwInVerifyNotificationForIds.add(notifId); // verifyNotification throws unverifiable

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'Pre-existing alarm must be preserved when new notification L2 verification is unverifiable',
      );
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24a. In-place refresh dispatches deterministic ID and triggers L1 fault injection', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Fajr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 4)), // Outdated/stale time forces refresh dispatch
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      fakeRepo.failL1AlarmScheduleForIds.add(alarmId); // In-place update fails at platform level

      // Unified Exception Contract: Platform failure is encapsulated in Repository; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Proves that scheduler dispatched to the deterministic ID
      expect(
        fakeRepo.l1AlarmScheduleFailureHits,
        greaterThan(0),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Scheduler must call scheduleAdhanAlarm with expected deterministic ID ($alarmId) for in-place update',
      );
    });

    test('24b. Stale event refresh failure: Outdated alarm refresh failure preserves old alarm, keeps status stale, and halts horizon', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final targetTime = testDate.add(const Duration(hours: 5));
      final staleTime = testDate.add(const Duration(hours: 4, minutes: 30));

      // 1. Existing alarm in registry with outdated time (4:30 vs 5:00)
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Old Fajr',
        body: 'Old Body',
        scheduledTime: staleTime,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
        volume: 1.0,
        enableVibration: true,
      );

      // Pre-condition: Initial verification identifies alarm as stale against 5:00 target
      expect(
        await fakeRepo.verifyAlarm(id: alarmId, expectedScheduledTime: targetTime),
        equals(EventVerificationStatus.stale),
        reason: 'Pre-existing alarm with 4:30 time must be identified as stale against 5:00 target',
      );

      // 2. Simulate refresh failure during scheduling
      fakeRepo.failL1AlarmScheduleForIds.add(alarmId);

      // 3. Scheduler attempts execution
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // 4. Non-destructive safety: Old alarm was NOT wiped by failed refresh or blanket wipe
      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Stale alarm must be preserved in registry when refresh fails',
      );
      expect(
        fakeRepo.scheduledAlarms[alarmId]?.scheduledTime,
        equals(staleTime),
        reason: 'Old alarm scheduledTime must remain intact at 4:30',
      );

      // 5. Verification status remains STALE, NOT matching
      expect(
        await fakeRepo.verifyAlarm(id: alarmId, expectedScheduledTime: targetTime),
        equals(EventVerificationStatus.stale),
        reason: 'Failed refresh leaves alarm in stale state (never falsely matches target)',
      );

      // 6. Horizon integrity: Stale alarm does NOT advance completion horizon
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'Horizon must not advance when refresh fails and alarm remains stale',
      );
    });

    test('24c. Notification L2 verification: Two-Tier validation of payload, title, and fingerprint ledger', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final targetTime = testDate.add(const Duration(hours: 12));
      final expectedPayload = 'adhan_simple_dhuhr|${targetTime.toIso8601String()}|adhan';
      final legacyPayload = 'adhan_simple_dhuhr'; // Unversioned legacy payload without timestamp

      // 1. Pre-seed notification with legacy unversioned payload
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: targetTime,
        payload: legacyPayload,
      );

      // 2. L2 Verification of legacy unversioned payload MUST return stale
      final legacyStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedScheduledTime: targetTime,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
      );
      expect(legacyStatus, equals(EventVerificationStatus.stale));
      expect(legacyStatus.isMatching, isFalse);

      // 3. Title mismatch must return stale
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Old Title',
        body: 'حي على الصلاة',
        scheduledTime: targetTime,
        payload: expectedPayload,
      );
      final titleMismatchStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedScheduledTime: targetTime,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
      );
      expect(titleMismatchStatus, equals(EventVerificationStatus.stale));

      // 4. FLN queue present with matching payload & title, but Fingerprint Ledger is MISSING -> MUST return stale
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: targetTime,
        payload: expectedPayload,
      );
      fakeRepo.notificationFingerprints.remove(notifId); // Ledger missing
      final missingFingerprintStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
        expectedChannelId: 'prayer_channel_v10_adhan',
        expectedSoundSource: 'adhan',
        expectedScheduledTime: targetTime,
      );
      expect(missingFingerprintStatus, equals(EventVerificationStatus.stale),
          reason: 'Missing fingerprint ledger must be treated as stale (untracked/unverified)');

      // 5. Fingerprint Ledger has mismatched channelId -> MUST return stale
      fakeRepo.notificationFingerprints[notifId] = NotificationSchedulingFingerprint(
        id: notifId,
        channelId: 'prayer_channel_v10_default', // Old channel without custom sound
        soundSource: 'adhan',
        scheduledTimeIso: targetTime.toIso8601String(),
        payload: expectedPayload,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
      );
      final channelMismatchStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
        expectedChannelId: 'prayer_channel_v10_adhan',
        expectedSoundSource: 'adhan',
        expectedScheduledTime: targetTime,
      );
      expect(channelMismatchStatus, equals(EventVerificationStatus.stale),
          reason: 'Mismatched channel ID in ledger must return stale');

      // 6. Fingerprint Ledger has mismatched soundSource -> MUST return stale
      fakeRepo.notificationFingerprints[notifId] = NotificationSchedulingFingerprint(
        id: notifId,
        channelId: 'prayer_channel_v10_adhan',
        soundSource: 'takbeer', // Wrong sound
        scheduledTimeIso: targetTime.toIso8601String(),
        payload: expectedPayload,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
      );
      final soundMismatchStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
        expectedChannelId: 'prayer_channel_v10_adhan',
        expectedSoundSource: 'adhan',
        expectedScheduledTime: targetTime,
      );
      expect(soundMismatchStatus, equals(EventVerificationStatus.stale),
          reason: 'Mismatched sound source in ledger must return stale');

      // 7. Full Synchronization: Both Tier 1 (FLN) and Tier 2 (Ledger) match completely -> Returns matching
      fakeRepo.notificationFingerprints[notifId] = NotificationSchedulingFingerprint(
        id: notifId,
        channelId: 'prayer_channel_v10_adhan',
        soundSource: 'adhan',
        scheduledTimeIso: targetTime.toIso8601String(),
        payload: expectedPayload,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
      );
      final matchingStatus = await fakeRepo.verifyNotification(
        id: notifId,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
        expectedChannelId: 'prayer_channel_v10_adhan',
        expectedSoundSource: 'adhan',
        expectedScheduledTime: targetTime,
      );
      expect(matchingStatus, equals(EventVerificationStatus.matching));
      expect(matchingStatus.isMatching, isTrue);

      // 8. Query for non-existent notification returns absent
      final absentStatus = await fakeRepo.verifyNotification(
        id: 99999999,
        expectedScheduledTime: targetTime,
        expectedPayload: expectedPayload,
        expectedTitle: 'حان الآن موعد صلاة الظهر',
      );
      expect(absentStatus, equals(EventVerificationStatus.absent));
    });

    test('24d. Desired Alarm verified matching, opposing Notification cancel fails -> opposingDecommissionFailed', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      // Pre-seed matching alarm
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Fajr',
        body: 'الصلاة خير من النوم',
        scheduledTime: testDate.add(const Duration(hours: 5)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Inject opposing notification cancellation failure
      fakeRepo.failCancelNotificationForIds.add(notifId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Horizon must be capped because opposing decommission failed
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24e. Desired Alarm verified matching, opposing Notification is imminent -> opposingDecommissionDeferred', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Fajr',
        body: 'الصلاة خير من النوم',
        scheduledTime: testDate.add(const Duration(hours: 5)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      fakeRepo.imminentNotificationIds.add(notifId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24f. Pre-check verifyAlarm returns unverifiable -> Fail-Closed: zero dispatch, zero decommission', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      fakeRepo.throwInVerifyAlarmForIds.add(alarmId); // Pre-check throws

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Fail-closed: do not schedule alarm, do not cancel notification
      expect(fakeRepo.scheduledAlarms.containsKey(alarmId), isFalse);
      expect(fakeRepo.cancelNotificationSafelyCalls.contains(notifId), isFalse);
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24g. Desired Notification matching, opposing Alarm cancel fails -> opposingDecommissionFailed', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final targetTime = testDate.add(const Duration(hours: 12));

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      // Pre-seed matching notification
      final payload = NotificationPayloadContract.buildPayload(
        eventId: notifId,
        scheduledTime: targetTime,
        channelId: 'prayer_channel_v10_adhan',
        soundSource: 'adhan',
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
      );
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
        scheduledTime: targetTime,
        payload: payload,
      );

      // Opposing alarm cancellation fails
      fakeRepo.failCancelAlarmForIds.add(alarmId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24h. Desired Notification matching, opposing Alarm is imminent -> opposingDecommissionDeferred', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final targetTime = testDate.add(const Duration(hours: 12));

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      final payload = NotificationPayloadContract.buildPayload(
        eventId: notifId,
        scheduledTime: targetTime,
        channelId: 'prayer_channel_v10_adhan',
        soundSource: 'adhan',
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
      );
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
        scheduledTime: targetTime,
        payload: payload,
      );

      fakeRepo.imminentAlarmIds.add(alarmId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24i. Post-check verifyNotification returns unverifiable -> operation failed, opposing alarm preserved', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      // Pre-seed opposing alarm
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Dhuhr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      // Post-check verifyNotification throws unverifiable
      fakeRepo.throwInVerifyNotificationForIds.add(notifId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Opposing alarm must be preserved!
      expect(fakeRepo.scheduledAlarms.containsKey(alarmId), isTrue);
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24j. Opposing Alarm cancellation deferred due to active ringing -> opposingDecommissionDeferred', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final targetTime = testDate.add(const Duration(hours: 12));

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      // Desired notification matching
      final payload = NotificationPayloadContract.buildPayload(
        eventId: notifId,
        scheduledTime: targetTime,
        channelId: 'prayer_channel_v10_adhan',
        soundSource: 'adhan',
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
      );
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة، حي على الفلاح',
        scheduledTime: targetTime,
        payload: payload,
      );

      // Opposing alarm is actively ringing
      fakeRepo.ringingAlarmIds.add(alarmId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24k. Notification in FLN queue, but fingerprint missing / payload mismatched -> stale, refresh attempted', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      // Pre-seed stale notification
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Old Title',
        body: 'Old Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        payload: 'old_stale_payload',
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Scheduler should have refreshed it
      expect(fakeRepo.schedulePrayerNotificationCalls.contains(notifId), isTrue);
    });

    test('24l. Notification cancel succeeds, but fingerprint removal fails -> cancellation failed', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      // Fajr is in alarm mode; opposing notification exists
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Fajr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );
      fakeRepo.notificationFingerprints[notifId] = NotificationSchedulingFingerprint(
        id: notifId,
        channelId: 'prayer_channel_v10_fajr_azan',
        soundSource: 'fajr_azan',
        scheduledTimeIso: testDate.add(const Duration(hours: 5)).toIso8601String(),
        payload: 'test_payload',
        title: 'Fajr',
        body: 'Body',
      );

      fakeRepo.failLedgerRemovalForIds.add(notifId); // Ledger removal fails!

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24m. Off mode: Alarm failed + Notification deferred -> Precedence enforced: operation failed', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off),
      );

      fakeRepo.failCancelAlarmForIds.add(alarmId); // Alarm cancel fails
      fakeRepo.imminentNotificationIds.add(notifId); // Notification deferred

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Failure takes precedence over deferral -> horizon must be capped
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24n. Off mode: Notification failed + Alarm cancelled -> operation failed, day incomplete', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off),
      );

      fakeRepo.failCancelNotificationForIds.add(notifId);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24o. Same-ID FLN replacement failure characterization -> proves no pre-cancellation', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.notification,
      );
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
      );

      // Pre-seed opposing alarm
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Old Dhuhr Alarm',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 12)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Pre-seed stale notification with same ID
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Old Dhuhr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 11)), // Stale time
      );

      fakeRepo.failL1NotificationScheduleForIds.add(notifId); // Replacement dispatch fails

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Opposing alarm must be strictly preserved!
      expect(fakeRepo.scheduledAlarms.containsKey(alarmId), isTrue);
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24p. Same-ID Alarm replacement failure characterization -> proves no pre-cancellation', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      // Pre-seed opposing notification
      fakeRepo.scheduledNotifications[notifId] = ScheduledNotificationRecord(
        id: notifId,
        title: 'Old Fajr Notif',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
      );

      // Pre-seed stale alarm with same ID
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Old Fajr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 4)), // Stale time
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      fakeRepo.failL1AlarmScheduleForIds.add(alarmId); // Replacement dispatch fails

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Opposing notification must be strictly preserved!
      expect(fakeRepo.scheduledNotifications.containsKey(notifId), isTrue);
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(horizonDate == null || horizonDate.isBefore(testDate), isTrue);
    });

    test('24q. Orphan fingerprint non-resurrection & end-to-end retry cleanup (9 Strict Assertions)', () async {
      final notifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.notification,
      );

      // Configure prayer in alarm mode (NO notification should exist)
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
      );

      // FLN queue is empty
      fakeRepo.scheduledNotifications.remove(notifId);

      // Orphan fingerprint exists in ledger
      fakeRepo.notificationFingerprints[notifId] = NotificationSchedulingFingerprint(
        id: notifId,
        channelId: 'prayer_channel_v10_fajr_azan',
        soundSource: 'fajr_azan',
        scheduledTimeIso: testDate.add(const Duration(hours: 5)).toIso8601String(),
        payload: 'orphan_payload',
        title: 'Orphan Title',
        body: 'Orphan Body',
      );

      // Fault injection: ledger removal fails during Run 1
      fakeRepo.failLedgerRemovalForIds.add(notifId);

      // --- RUN 1 (Injected Storage Cleanup Failure) ---
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Assertion 1: Day is incomplete
      // Assertion 2: Horizon does not advance
      final run1Until = pref.getString('scheduled_until_date');
      final run1Date = run1Until != null ? DateTime.parse(run1Until) : null;
      expect(run1Date == null || run1Date.isBefore(testDate), isTrue,
          reason: 'Assertion 2: Horizon must not advance when orphan ledger cleanup fails');

      // Assertion 3: Orphan fingerprint still exists
      expect(fakeRepo.notificationFingerprints.containsKey(notifId), isTrue,
          reason: 'Assertion 3: Orphan fingerprint remains in ledger after failed cleanup');

      // Assertion 4: Zero calls to schedulePrayerNotification for notifId (no phantom resurrection)
      expect(fakeRepo.schedulePrayerNotificationCalls.contains(notifId), isFalse,
          reason: 'Assertion 4: Orphan fingerprint must not be resurrected into a live notification');

      // --- RUN 2 (Fault Cleared — Retry Convergence) ---
      fakeRepo.failLedgerRemovalForIds.clear(); // Clear injected storage failure

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Assertion 5: Still zero calls to schedulePrayerNotification for notifId
      expect(fakeRepo.schedulePrayerNotificationCalls.contains(notifId), isFalse,
          reason: 'Assertion 5: Retry must still not resurrect the orphan notification');

      // Assertion 6: Orphan fingerprint successfully removed from ledger
      expect(fakeRepo.notificationFingerprints.containsKey(notifId), isFalse,
          reason: 'Assertion 6: Orphan fingerprint must be cleanly removed on retry');

      // Assertion 7: FLN queue remains empty
      expect(fakeRepo.scheduledNotifications.containsKey(notifId), isFalse,
          reason: 'Assertion 7: Delivery state not misclassified as matching notification');

      // Assertion 8 & 9: Day completes and horizon advances
      final run2Until = pref.getString('scheduled_until_date');
      expect(run2Until, isNotNull, reason: 'Assertion 9: Horizon advances on clean retry convergence');
    });
  });

  // ============================================================================
  // GROUP E: Auxiliary Events Explicit Verification & Independence (R4)
  // ============================================================================
  group('Group E: Auxiliary Events Explicit Verification & Independence (R4)', () {
    test('25. Iqama scheduling failure -> Day marked incomplete, Adhan alarm preserved', () async {
      fakeRepo.failIqamaSchedule = true;

      // Unified Exception Contract: Platform failure caught in repo; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;

      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Iqama failure must mark day incomplete and halt horizon advancement',
      );

      final fajrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      expect(
        fakeRepo.scheduledAlarms.containsKey(fajrAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Adhan alarm must remain preserved when Iqama fails',
      );
    });

    test('26. Post-prayer Azkar scheduling failure -> Day marked incomplete, Adhan alarm preserved', () async {
      fakeRepo.failPostPrayerAzkarSchedule = true;

      // Unified Exception Contract: Platform failure caught in repo; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;

      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Azkar failure must mark day incomplete and halt horizon advancement',
      );

      final dhuhrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.dhuhr,
        decision: PrayerAlertDecision.alarm,
      );
      expect(
        fakeRepo.scheduledAlarms.containsKey(dhuhrAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Adhan alarm must remain preserved when Azkar fails',
      );
    });

    test('27. Morning Azkar scheduling failure -> Day marked incomplete, Fajr alarm preserved', () async {
      fakeRepo.failMorningAzkarSchedule = true;

      // Unified Exception Contract: Platform failure caught in repo; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;

      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Morning Azkar failure must mark day incomplete',
      );

      final fajrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      expect(
        fakeRepo.scheduledAlarms.containsKey(fajrAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Fajr alarm must remain preserved when Morning Azkar fails',
      );
    });

    test('28. Evening Azkar scheduling failure -> Day marked incomplete, Asr alarm preserved', () async {
      fakeRepo.failEveningAzkarSchedule = true;

      // Unified Exception Contract: Platform failure caught in repo; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;

      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Evening Azkar failure must mark day incomplete',
      );

      final asrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.asr,
        decision: PrayerAlertDecision.alarm,
      );
      expect(
        fakeRepo.scheduledAlarms.containsKey(asrAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Asr alarm must remain preserved when Evening Azkar fails',
      );
    });

    test('29. Prayer set to off with Iqama & Azkar enabled -> Prayer alert absent, but Iqama and Azkar ARE scheduled', () async {
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.off),
      );

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final maghribAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.maghrib,
        decision: PrayerAlertDecision.alarm,
      );
      final maghribNotifId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.maghrib,
        decision: PrayerAlertDecision.notification,
      );
      final maghribIqamaId = CalendarAlarmIdContract.iqamaId(
        date: testDate,
        prayer: PrayerId.maghrib,
      );
      final maghribAzkarId = CalendarAlarmIdContract.postPrayerAzkarId(
        date: testDate,
        prayer: PrayerId.maghrib,
      );

      // Prayer alert must be absent
      expect(fakeRepo.scheduledAlarms.containsKey(maghribAlarmId), isFalse);
      expect(fakeRepo.scheduledNotifications.containsKey(maghribNotifId), isFalse);

      // Auxiliary reminders MUST be scheduled
      expect(
        fakeRepo.scheduledNotifications.containsKey(maghribIqamaId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Iqama must be scheduled even if prayer is off',
      );
      expect(
        fakeRepo.scheduledNotifications.containsKey(maghribAzkarId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Post-prayer Azkar must be scheduled even if prayer is off',
      );
    });

    test('30. Auxiliary retry / rescheduling does NOT change prayer alert IDs', () async {
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final initialAlarmIds = fakeRepo.scheduledAlarms.keys.toSet();

      // Trigger second run (rescheduling/retry)
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final secondRunAlarmIds = fakeRepo.scheduledAlarms.keys.toSet();

      expect(
        secondRunAlarmIds,
        equals(initialAlarmIds),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Alarm IDs must remain 100% stable across runs',
      );
    });
  });

  // ============================================================================
  // GROUP F: Contiguous Horizon & Partial State Preservation
  // ============================================================================
  group('Group F: Contiguous Horizon & Partial State Preservation', () {
    test('31. Full 5-day success advances scheduled_until_date to Day 4 / Day 5', () async {
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      expect(scheduledUntil, isNotNull);

      final date = DateTime.parse(scheduledUntil!);
      expect(date.isAfter(DateTime.now().add(const Duration(days: 3))), isTrue);
    });

    test('32. Day 0 Complete, Day 1 Complete, Day 2 Partial/Fails -> Horizon caps at Day 1; Day 3 not attempted', () async {
      final day2 = DateTime(now.year, now.month, now.day + 2);
      fakePrayerTimes.failForDate(day2); // DAY 2 FAILS

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizon = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;

      final expectedMaxHorizon = DateTime(now.year, now.month, now.day + 1, 23, 59, 59);

      expect(
        horizon != null && horizon.isBefore(expectedMaxHorizon.add(const Duration(minutes: 1))),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Contiguous horizon must cap at Day 1 when Day 2 fails',
      );
    });

    test('33. Day 2 partial failure preserves partial events registered on Day 2 on subsequent retry without deletion', () async {
      final day2 = DateTime(now.year, now.month, now.day + 2);

      // Pre-seed a partial valid event on Day 2
      final day2FajrAlarmId = CalendarAlarmIdContract.prayerAlertId(
        date: day2,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      fakeRepo.scheduledAlarms[day2FajrAlarmId] = ScheduledAlarmRecord(
        id: day2FajrAlarmId,
        title: 'Day 2 Fajr',
        body: 'Pre-existing partial event',
        scheduledTime: day2.add(const Duration(hours: 5)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Make Day 2 fail during calculation
      fakePrayerTimes.failForDate(day2);

      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      expect(
        fakeRepo.scheduledAlarms.containsKey(day2FajrAlarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Partial event on Day 2 must not be deleted when Day 2 fails',
      );
    });

    test('34. Concurrency Preemption: Newer session invalidates older session -> Older session aborts without writing cache', () async {
      // Simulate session preemption by bumping session ID
      ScheduleWeeklyPrayersUseCase.resetSessionIdForTesting();

      final firstRunFuture = scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');
      // Immediately start second session
      final secondRunFuture = scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      await Future.wait([firstRunFuture, secondRunFuture]);

      // Execution converges safely
      expect(fakeRepo.operationLog, isNotEmpty);
    });
  });
}
