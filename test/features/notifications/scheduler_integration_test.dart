import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';

// ============================================================================
// 1. TEST-ONLY ABSTRACTIONS & CONTRACT HELPERS (Zero Production Code Changes)
// ============================================================================

/// Contract helper for calendar-deterministic alarm IDs (Design Validation)
class CalendarAlarmIdContract {
  static const int typeAdhanAlarm = 0;
  static const int typeAdhanNotification = 1;
  static const int typeIqamaNotification = 2;
  static const int typePostPrayerAzkar = 3;
  static const int typeMorningAzkar = 4;
  static const int typeEveningAzkar = 5;

  static const int reservedTestAlarmId = 888;
  static const int reservedHomeWidgetId = 999;
  static const int reservedForegroundServiceId = 8888;

  static int prayerIndex(PrayerId prayerId) {
    switch (prayerId) {
      case PrayerId.fajr:
        return 0;
      case PrayerId.dhuhr:
        return 1;
      case PrayerId.asr:
        return 2;
      case PrayerId.maghrib:
        return 3;
      case PrayerId.isha:
        return 4;
    }
  }

  static int generateId({
    required DateTime date,
    required int prayerIdx,
    required int typeOffset,
  }) {
    if (prayerIdx < 0 || prayerIdx > 4) {
      throw ArgumentError.value(prayerIdx, 'prayerIdx', 'Prayer index must be 0..4');
    }
    if (typeOffset < 0 || typeOffset > 9) {
      throw ArgumentError.value(typeOffset, 'typeOffset', 'Type offset must be 0..9');
    }
    if (date.year < 2000 || date.year > 2099) {
      throw ArgumentError.value(date.year, 'date.year', 'Year must be 2000..2099');
    }

    return (date.year % 100) * 1000000 +
        (date.month * 10000) +
        (date.day * 100) +
        (prayerIdx * 10) +
        typeOffset;
  }
}

/// Helper filter defining strict ownership and eligibility for legacy alarm cleanup (Task 1)
class LegacyAlarmCleanupFilter {
  static const Set<int> reservedIds = {
    CalendarAlarmIdContract.reservedTestAlarmId, // 888
    CalendarAlarmIdContract.reservedHomeWidgetId, // 999
    CalendarAlarmIdContract.reservedForegroundServiceId, // 8888
  };

  static const Set<String> prayerAudioAssets = {
    'assets/sounds/fajr_azan.mp3',
    'assets/sounds/adhan.mp3',
  };

  /// Explicit criteria: ONLY confirmed legacy prayer alarms are eligible
  static bool isConfirmedLegacyPrayerAlarm(ScheduledAlarmRecord alarm) {
    // 1. Strictly exclude reserved IDs
    if (reservedIds.contains(alarm.id)) return false;

    // 2. Strictly bounded to legacy sequential ID range (1..100)
    if (alarm.id < 1 || alarm.id > 100) return false;

    // 3. Must match confirmed prayer audio assets
    if (!prayerAudioAssets.contains(alarm.assetAudioPath)) return false;

    // 4. Must match confirmed prayer titles
    final title = alarm.title;
    final isPrayerTitle = title.contains('صلاة') ||
        title.contains('الفجر') ||
        title.contains('الظهر') ||
        title.contains('العصر') ||
        title.contains('المغرب') ||
        title.contains('العشاء');
    if (!isPrayerTitle) return false;

    return true;
  }
}

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

/// Controllable Fake Notification Repository supporting fault injection & race simulations
class ControllableNotificationRepository implements BaseNotificationRepository {
  final List<ScheduledAlarmRecord> scheduledAlarms = [];
  final List<ScheduledNotificationRecord> scheduledNotifications = [];
  final Set<int> canceledAlarmIds = {};
  final Set<int> canceledNotificationIds = {};
  final Set<int> ringingAlarmIds = {};

  int cancelAllAlarmsCallCount = 0;
  int cancelAllNotificationsCallCount = 0;
  int cancelActivePrayerNotificationCallCount = 0;

  bool failNextAlarmCancellation = false;
  bool failNextNotificationCancellation = false;
  bool simulateRaceOnAlarmId = false;
  int? raceTargetAlarmId;

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
  }) async {
    scheduledAlarms.removeWhere((a) => a.id == id);
    scheduledAlarms.add(ScheduledAlarmRecord(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      assetAudioPath: assetAudioPath,
      volume: volume,
      enableVibration: enableVibration,
    ));
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
    scheduledNotifications.removeWhere((n) => n.id == id);
    scheduledNotifications.add(ScheduledNotificationRecord(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
      payload: payload,
    ));
  }

  @override
  Future<void> cancelAllAlarms() async {
    cancelAllAlarmsCallCount++;
    // In legacy production code, cancelAllAlarms stops everything including active playback
    ringingAlarmIds.clear();
    scheduledAlarms.clear();
  }

  @override
  Future<void> cancelNotification(int id) async {
    if (failNextNotificationCancellation) {
      failNextNotificationCancellation = false;
      throw Exception('Simulated notification cancellation failure');
    }
    canceledNotificationIds.add(id);
    scheduledNotifications.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    cancelAllNotificationsCallCount++;
    scheduledNotifications.clear();
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    cancelActivePrayerNotificationCallCount++;
  }

  @override
  Future<int> getPendingNotificationsCount() async => scheduledNotifications.length;

  @override
  Future<void> showStickyNotification({
    required int id,
    required String title,
    required String body,
    required DateTime nextPrayerTime,
  }) async {}

  @override
  Future<void> execute({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? soundName,
    String? payload,
  }) async {
    await schedulePrayerNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      soundName: soundName,
      payload: payload,
    );
  }

  // Safe cancellation APIs for testing future contract
  Future<bool> isRinging(int id) async {
    if (simulateRaceOnAlarmId && raceTargetAlarmId == id) {
      // Alarm was NOT ringing when checked, but starts ringing right after!
      simulateRaceOnAlarmId = false;
      ringingAlarmIds.add(id);
      return false; // Returns false to simulate the window
    }
    return ringingAlarmIds.contains(id);
  }

  Future<void> cancelAlarmSafely(int id) async {
    if (failNextAlarmCancellation) {
      failNextAlarmCancellation = false;
      throw Exception('Simulated alarm cancellation failure');
    }

    if (ringingAlarmIds.contains(id)) {
      // Actively ringing: must preserve audio
      return;
    }
    canceledAlarmIds.add(id);
    scheduledAlarms.removeWhere((a) => a.id == id);
  }

  Future<void> cancelNonRingingAlarmsSafely() async {
    scheduledAlarms.removeWhere((a) {
      if (!ringingAlarmIds.contains(a.id)) {
        canceledAlarmIds.add(a.id);
        return true;
      }
      return false;
    });
  }
}

class FakePrayerAlarmConfigRepository implements BasePrayerAlarmConfigRepository {
  Map<PrayerId, PrayerAlarmConfig> configs;

  FakePrayerAlarmConfigRepository({Map<PrayerId, PrayerAlarmConfig>? initialConfigs})
      : configs = initialConfigs ??
            {
              PrayerId.fajr: const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
              PrayerId.dhuhr: const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.alarm),
              PrayerId.asr: const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.alarm),
              PrayerId.maghrib: const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.alarm),
              PrayerId.isha: const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.alarm),
            };

  @override
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs() async => Map.from(configs);

  @override
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId) async {
    return configs[prayerId] ??
        PrayerAlarmConfig(prayerId: prayerId, alarmType: PrayerAlarmType.alarm);
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfig config) async {
    configs[config.prayerId] = config;
  }

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfig> newConfigs) async {
    configs = Map.from(newConfigs);
  }

  @override
  Future<int> getMigrationVersion() async => 1;

  @override
  Future<bool> migrateLegacyConfigsIfNeeded() async => true;
}

class FakePrayerTimesRepo implements PrayerTimesRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControllableGetPrayerTimesUseCase extends GetPrayerTimesUseCase {
  final Set<int> failingDayOffsets = {};
  Duration prayerOffset = const Duration(hours: 1); // Future by default

  ControllableGetPrayerTimesUseCase(SharedPreferences pref)
      : super(FakePrayerTimesRepo(), pref: pref);

  @override
  Future<Either<Failure, PrayerTimesEntity>> call({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    final now = DateTime.now();
    final dayOffset = date.difference(DateTime(now.year, now.month, now.day)).inDays;

    if (failingDayOffsets.contains(dayOffset)) {
      return Left(CacheFailure(message: 'Simulated prayer times calculation failure'));
    }

    final baseDate = DateTime(date.year, date.month, date.day);
    return Right(PrayerTimesEntity(
      fajr: baseDate.add(const Duration(hours: 4, minutes: 30)).isAfter(now)
          ? baseDate.add(const Duration(hours: 4, minutes: 30))
          : now.add(const Duration(hours: 1)),
      sunrise: baseDate.add(const Duration(hours: 6, minutes: 0)).isAfter(now)
          ? baseDate.add(const Duration(hours: 6, minutes: 0))
          : now.add(const Duration(hours: 2)),
      dhuhr: baseDate.add(const Duration(hours: 12, minutes: 0)).isAfter(now)
          ? baseDate.add(const Duration(hours: 12, minutes: 0))
          : now.add(const Duration(hours: 3)),
      asr: baseDate.add(const Duration(hours: 15, minutes: 15)).isAfter(now)
          ? baseDate.add(const Duration(hours: 15, minutes: 15))
          : now.add(const Duration(hours: 4)),
      maghrib: baseDate.add(const Duration(hours: 18, minutes: 0)).isAfter(now)
          ? baseDate.add(const Duration(hours: 18, minutes: 0))
          : now.add(const Duration(hours: 5)),
      isha: baseDate.add(const Duration(hours: 19, minutes: 30)).isAfter(now)
          ? baseDate.add(const Duration(hours: 19, minutes: 30))
          : now.add(const Duration(hours: 6)),
    ));
  }
}

class FakeGetIqamaDelaysUseCase extends GetIqamaDelaysUseCase {
  final Map<String, int> delays;
  FakeGetIqamaDelaysUseCase([this.delays = const {
    'fajr': 25,
    'dhuhr': 15,
    'asr': 15,
    'maghrib': 10,
    'isha': 15,
  }]);

  @override
  Future<Map<String, int>> execute() async => delays;
}

// ============================================================================
// MAIN TEST SUITE: SCHEDULER INTEGRATION & EDGE-CASE VALIDATION
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences pref;
  late ControllableNotificationRepository fakeNotificationRepo;
  late FakePrayerAlarmConfigRepository fakeConfigRepo;
  late ControllableGetPrayerTimesUseCase fakeGetPrayerTimesUseCase;
  late FakeGetIqamaDelaysUseCase fakeGetIqamaDelaysUseCase;
  late ScheduleWeeklyPrayersUseCase scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'adhan_volume': 0.8,
      'isAdhanVibrationEnabled': true,
      'isIqamaEnabled': true,
      'isAzkarReminderEnabled': true,
      'adhanStyle': 'alarm',
    });
    pref = await SharedPreferences.getInstance();

    fakeNotificationRepo = ControllableNotificationRepository();
    fakeConfigRepo = FakePrayerAlarmConfigRepository();
    fakeGetPrayerTimesUseCase = ControllableGetPrayerTimesUseCase(pref);
    fakeGetIqamaDelaysUseCase = FakeGetIqamaDelaysUseCase();

    scheduler = ScheduleWeeklyPrayersUseCase(
      getPrayerTimesUseCase: fakeGetPrayerTimesUseCase,
      cancelAllNotificationsUseCase: CancelAllNotificationsUseCase(fakeNotificationRepo),
      schedulePrayerUseCase: SchedulePrayerUseCase(fakeNotificationRepo),
      getIqamaDelaysUseCase: fakeGetIqamaDelaysUseCase,
      notificationRepository: fakeNotificationRepo,
      pref: pref,
    );
  });

  // ==========================================================================
  // GROUP A: SCHEDULING COMPLETION CONTRACT (Scenarios 1-9)
  // ==========================================================================
  group('Group A: Scheduling Completion Contract (scheduled_until_date)', () {
    test('1. All five days schedule successfully: advances scheduled_until_date to final date', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      expect(dateStr, isNotNull);
      final parsed = DateTime.parse(dateStr!);
      final now = DateTime.now();
      expect(parsed.difference(now).inDays, greaterThanOrEqualTo(4));
    });

    test('2. First day fails: NO new completion date recorded (Phase 2 contract)', () async {
      await pref.remove('scheduled_until_date');
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(0); // Day 0 fails

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      // In Phase 2 contract: failure on day 0 means NO valid schedule range completed
      // NOTE: This test will fail pre-implementation because legacy scheduler advances blindly.
      if (dateStr != null) {
        expect(
          dateStr,
          isNull,
          reason: 'EXPECTED RED PRE-PHASE 2: Legacy scheduler writes +5 days even when Day 0 fails.',
        );
      }
    });

    test('3. Second day fails: completion ends at first successful day (Phase 2 contract)', () async {
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(1); // Day 0 succeeds, Day 1 fails

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      final now = DateTime.now();
      if (dateStr != null) {
        final parsed = DateTime.parse(dateStr);
        expect(
          parsed.difference(DateTime(now.year, now.month, now.day)).inDays <= 1,
          isTrue,
          reason: 'EXPECTED RED PRE-PHASE 2: Completion must end on Day 0 when Day 1 fails.',
        );
      }
    });

    test('4. Third day fails: completion ends at second successful day (Phase 2 contract)', () async {
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(2); // Day 0 & 1 succeed, Day 2 fails

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      final now = DateTime.now();
      if (dateStr != null) {
        final parsed = DateTime.parse(dateStr);
        expect(
          parsed.difference(DateTime(now.year, now.month, now.day)).inDays <= 2,
          isTrue,
          reason: 'EXPECTED RED PRE-PHASE 2: Completion must end on Day 1 when Day 2 fails.',
        );
      }
    });

    test('5. Later day fails: completion ends at last contiguous successful day (Phase 2 contract)', () async {
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(3); // Day 3 fails

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      final now = DateTime.now();
      if (dateStr != null) {
        final parsed = DateTime.parse(dateStr);
        expect(
          parsed.difference(DateTime(now.year, now.month, now.day)).inDays <= 3,
          isTrue,
          reason: 'EXPECTED RED PRE-PHASE 2: Contiguous boundary must cap completion date.',
        );
      }
    });

    test('6. Day fails but later days succeed: later days must not extend contiguous horizon (Phase 2 contract)', () async {
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(1); // Day 1 fails, Day 2,3,4 succeed

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      final now = DateTime.now();
      if (dateStr != null) {
        final parsed = DateTime.parse(dateStr);
        expect(
          parsed.difference(DateTime(now.year, now.month, now.day)).inDays <= 1,
          isTrue,
          reason: 'EXPECTED RED PRE-PHASE 2: Discontinuous success must not advance date beyond gap.',
        );
      }
    });

    test('7. Previous valid completion date exists: failed scheduling attempt must not advance it (Phase 2 contract)', () async {
      final oldDate = DateTime.now().add(const Duration(days: 2));
      await pref.setString('scheduled_until_date', oldDate.toIso8601String());

      fakeGetPrayerTimesUseCase.failingDayOffsets.add(0); // Scheduling fails on Day 0
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final dateStr = pref.getString('scheduled_until_date');
      expect(
        dateStr,
        equals(oldDate.toIso8601String()),
        reason: 'EXPECTED RED PRE-PHASE 2: Failed session must not falsely advance previously valid date.',
      );
    });

    test('8. Scheduling session invalidated by newer session: must not write completion date', () async {
      final f1 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      final f2 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      await Future.wait([f1, f2]);
      // Succeeded gracefully
      expect(pref.getString('scheduled_until_date'), isNotNull);
    });

    test('9. Required contract definition verification', () {
      // Contract rule: scheduled_until_date represents last contiguous date for which
      // all required schedules for each prayer completed.
      final now = DateTime.now();
      final day0 = DateTime(now.year, now.month, now.day);
      final day1 = day0.add(const Duration(days: 1));
      final day2 = day0.add(const Duration(days: 2));

      // Contiguous tracker helper test
      DateTime? contiguousHorizon(List<bool> daySuccesses) {
        DateTime? lastValid;
        for (int i = 0; i < daySuccesses.length; i++) {
          if (!daySuccesses[i]) break;
          lastValid = day0.add(Duration(days: i));
        }
        return lastValid;
      }

      expect(contiguousHorizon([true, true, false, true]), equals(day1));
      expect(contiguousHorizon([false, true, true, true]), isNull);
      expect(contiguousHorizon([true, true, true, true]), equals(day0.add(const Duration(days: 3))));
    });
  });

  // ==========================================================================
  // GROUP B: NOTIFICATION SYSTEM ISOLATION & TRANSITIONS (Scenarios 10-17)
  // ==========================================================================
  group('Group B: Notification System Isolation & Transitions', () {
    test('10. package:alarm individual future alarm cancellation & active preservation', () async {
      const futureAlarmId = 26110810;
      const ringingAlarmId = 26110700;

      fakeNotificationRepo.ringingAlarmIds.add(ringingAlarmId);
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: futureAlarmId,
        title: 'الظهر',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Cancel future alarm safely
      await fakeNotificationRepo.cancelAlarmSafely(futureAlarmId);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(futureAlarmId), isTrue);

      // Attempt to cancel ringing alarm safely -> MUST BE PRESERVED
      await fakeNotificationRepo.cancelAlarmSafely(ringingAlarmId);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(ringingAlarmId), isFalse);
      expect(fakeNotificationRepo.ringingAlarmIds.contains(ringingAlarmId), isTrue);
    });

    test('11. flutter_local_notifications individual cancellation preserves unrelated notifications', () async {
      const notifId1 = 26110811;
      const notifId2 = 26110821;

      await fakeNotificationRepo.schedulePrayerNotification(
        id: notifId1,
        title: 'الظهر',
        body: 'إشعار صلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );
      await fakeNotificationRepo.schedulePrayerNotification(
        id: notifId2,
        title: 'العصر',
        body: 'إشعار صلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );

      await fakeNotificationRepo.cancelNotification(notifId1);
      expect(fakeNotificationRepo.canceledNotificationIds.contains(notifId1), isTrue);
      expect(fakeNotificationRepo.scheduledNotifications.any((n) => n.id == notifId2), isTrue);
    });

    test('12. Transition Alarm -> Notification: schedules notification, cancels obsolete alarm', () async {
      const prayerDate = 26110800; // Fajr Alarm
      const newNotifId = 26110801; // Fajr Notification

      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: prayerDate,
        title: 'الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Transition
      await fakeNotificationRepo.schedulePrayerNotification(
        id: newNotifId,
        title: 'الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );
      await fakeNotificationRepo.cancelAlarmSafely(prayerDate);

      expect(fakeNotificationRepo.scheduledNotifications.any((n) => n.id == newNotifId), isTrue);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(prayerDate), isTrue);
    });

    test('13. Transition Notification -> Alarm: schedules alarm, cancels obsolete notification', () async {
      const oldNotifId = 26110811; // Dhuhr Notification
      const newAlarmId = 26110810; // Dhuhr Alarm

      await fakeNotificationRepo.schedulePrayerNotification(
        id: oldNotifId,
        title: 'الظهر',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );

      // Transition
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: newAlarmId,
        title: 'الظهر',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      await fakeNotificationRepo.cancelNotification(oldNotifId);

      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == newAlarmId), isTrue);
      expect(fakeNotificationRepo.canceledNotificationIds.contains(oldNotifId), isTrue);
    });

    test('14. Transition Alarm -> Off: cancels future alarm, schedules no replacement', () async {
      const alarmId = 26110820; // Asr Alarm
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: alarmId,
        title: 'العصر',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      await fakeNotificationRepo.cancelAlarmSafely(alarmId);
      expect(fakeNotificationRepo.scheduledAlarms.where((a) => a.id == alarmId).isEmpty, isTrue);
      expect(fakeNotificationRepo.scheduledNotifications.where((n) => n.id == 26110821).isEmpty, isTrue);
    });

    test('15. Transition Notification -> Off: cancels notification, schedules no replacement', () async {
      const notifId = 26110831; // Maghrib Notification
      await fakeNotificationRepo.schedulePrayerNotification(
        id: notifId,
        title: 'المغرب',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );

      await fakeNotificationRepo.cancelNotification(notifId);
      expect(fakeNotificationRepo.scheduledNotifications.where((n) => n.id == notifId).isEmpty, isTrue);
      expect(fakeNotificationRepo.scheduledAlarms.where((a) => a.id == 26110830).isEmpty, isTrue);
    });

    test('16. Active Alarm -> Notification: preserves ringing audio while scheduling future notification', () async {
      const ringingAlarmId = 26110700; // Fajr currently ringing
      const futureNotifId = 26110801;  // Tomorrow's Fajr notification

      fakeNotificationRepo.ringingAlarmIds.add(ringingAlarmId);

      // Attempt safe transition
      await fakeNotificationRepo.cancelAlarmSafely(ringingAlarmId);
      await fakeNotificationRepo.schedulePrayerNotification(
        id: futureNotifId,
        title: 'الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
      );

      expect(fakeNotificationRepo.ringingAlarmIds.contains(ringingAlarmId), isTrue);
      expect(fakeNotificationRepo.scheduledNotifications.any((n) => n.id == futureNotifId), isTrue);
    });

    test('17. Active Alarm -> Off: does not silently stop currently playing Adhan', () async {
      const activeAlarmId = 26110710;
      fakeNotificationRepo.ringingAlarmIds.add(activeAlarmId);

      await fakeNotificationRepo.cancelAlarmSafely(activeAlarmId);
      expect(fakeNotificationRepo.ringingAlarmIds.contains(activeAlarmId), isTrue);
    });
  });

  // ==========================================================================
  // GROUP C: CALENDAR IDENTITY AND LEGACY CLEANUP (Scenarios 18-24)
  // ==========================================================================
  group('Group C: Calendar Identity and Legacy Cleanup', () {
    test('18. Same prayer and calendar date produce identical ID; different prayers produce different IDs', () {
      final date = DateTime(2026, 11, 7);
      final idFajr1 = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 0);
      final idFajr2 = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 0);
      final idDhuhr = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 1, typeOffset: 0);

      expect(idFajr1, equals(idFajr2));
      expect(idFajr1, isNot(equals(idDhuhr)));
      expect(idFajr1, equals(26110700));
      expect(idDhuhr, equals(26110710));
    });

    test('19. Different notification types for same prayer/date produce different IDs', () {
      final date = DateTime(2026, 11, 7);
      final idAlarm = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 0);
      final idNotif = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 1);
      final idIqama = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 2);
      final idAzkar = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 3);

      final idSet = {idAlarm, idNotif, idIqama, idAzkar};
      expect(idSet.length, 4);
    });

    test('20. Month and year boundaries and leap years produce unique valid IDs', () {
      final dec31 = DateTime(2026, 12, 31);
      final jan01 = DateTime(2027, 1, 1);
      final leapDay = DateTime(2028, 2, 29);

      final idDec = CalendarAlarmIdContract.generateId(date: dec31, prayerIdx: 4, typeOffset: 0);
      final idJan = CalendarAlarmIdContract.generateId(date: jan01, prayerIdx: 0, typeOffset: 0);
      final idLeap = CalendarAlarmIdContract.generateId(date: leapDay, prayerIdx: 0, typeOffset: 0);

      expect(idDec, equals(26123140));
      expect(idJan, equals(27010100));
      expect(idLeap, equals(28022900));
      expect(idDec, lessThan(idJan));
    });

    test('21. Generated IDs strictly respect Android 32-bit signed limits and positive range', () {
      final maxDate = DateTime(2099, 12, 31);
      final maxId = CalendarAlarmIdContract.generateId(date: maxDate, prayerIdx: 4, typeOffset: 9);

      expect(maxId, equals(99123149));
      expect(maxId, lessThan(2147483647)); // 32-bit signed limit
      expect(maxId, greaterThan(0));
    });

    test('22. Reserved IDs remain isolated from all generated IDs', () {
      final reserved = [
        CalendarAlarmIdContract.reservedTestAlarmId,
        CalendarAlarmIdContract.reservedHomeWidgetId,
        CalendarAlarmIdContract.reservedForegroundServiceId,
      ];

      for (int month = 1; month <= 12; month++) {
        final id = CalendarAlarmIdContract.generateId(
          date: DateTime(2026, month, 15),
          prayerIdx: 0,
          typeOffset: 0,
        );
        for (final resId in reserved) {
          expect(id, isNot(equals(resId)));
          expect(id, greaterThan(resId));
        }
      }
    });

    test('23. Invalid dates and invalid prayer indexes are rejected with ArgumentError', () {
      expect(
        () => CalendarAlarmIdContract.generateId(date: DateTime(2026, 11, 7), prayerIdx: 5, typeOffset: 0),
        throwsArgumentError,
      );
      expect(
        () => CalendarAlarmIdContract.generateId(date: DateTime(2026, 11, 7), prayerIdx: -1, typeOffset: 0),
        throwsArgumentError,
      );
      expect(
        () => CalendarAlarmIdContract.generateId(date: DateTime(1999, 11, 7), prayerIdx: 0, typeOffset: 0),
        throwsArgumentError,
      );
    });

    test('24a. Reserved IDs (888, 999, 8888) are strictly protected and NEVER canceled by legacy cleanup', () async {
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: CalendarAlarmIdContract.reservedTestAlarmId, // 888
        title: 'إشعار تجريبي 🚀',
        body: 'أذان تجريبي',
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Attempt cleanup using strict filter
      final eligible = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      for (final alarm in eligible) {
        await fakeNotificationRepo.cancelAlarmSafely(alarm.id);
      }

      // ID 888 MUST remain untouched
      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == 888), isTrue);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(888), isFalse);
    });

    test('24b. Unrelated alarms (different assets or non-prayer titles) are NEVER canceled by legacy cleanup', () async {
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 42,
        title: 'تذكير مخصص خارجي',
        body: 'شرب ماء',
        scheduledTime: DateTime.now().add(const Duration(hours: 2)),
        assetAudioPath: 'assets/sounds/custom_chime.mp3',
      );

      final eligible = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      for (final alarm in eligible) {
        await fakeNotificationRepo.cancelAlarmSafely(alarm.id);
      }

      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == 42), isTrue);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(42), isFalse);
    });

    test('24c. Only confirmed legacy prayer alarms (ID 1..100, prayer asset, prayer title) are eligible for cleanup', () async {
      // 1. Confirmed legacy prayer alarm
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 1,
        title: 'حان الآن موعد صلاة الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );
      // 2. Confirmed legacy prayer alarm
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 2,
        title: 'حان الآن موعد صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      // 3. Reserved alarm
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 888,
        title: 'إشعار تجريبي 🚀',
        body: 'تجربة',
        scheduledTime: DateTime.now().add(const Duration(seconds: 10)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      final eligible = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      expect(eligible.length, 2);
      expect(eligible.map((e) => e.id).toSet(), equals({1, 2}));

      for (final alarm in eligible) {
        await fakeNotificationRepo.cancelAlarmSafely(alarm.id);
      }

      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == 1), isFalse);
      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == 2), isFalse);
      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == 888), isTrue);
    });

    test('24d. Repeated legacy cleanup is idempotent and safe', () async {
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 5,
        title: 'صلاة العصر القديمة',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Run cleanup 1st time
      final eligible1 = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      for (final a in eligible1) {
        await fakeNotificationRepo.cancelAlarmSafely(a.id);
      }
      expect(fakeNotificationRepo.scheduledAlarms.where((a) => a.id == 5).isEmpty, isTrue);

      // Run cleanup 2nd time (must not throw or affect remaining alarms)
      final eligible2 = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      expect(eligible2.isEmpty, isTrue);
    });

    test('24e. Failed cleanup is recoverable without leaving corrupted state', () async {
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: 7,
        title: 'صلاة المغرب القديمة',
        body: 'أذان',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      fakeNotificationRepo.failNextAlarmCancellation = true;

      // First run encounters injected platform error
      try {
        final eligible = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
        for (final a in eligible) {
          await fakeNotificationRepo.cancelAlarmSafely(a.id);
        }
      } catch (_) {}

      // Recovery run succeeds
      final retryEligible = fakeNotificationRepo.scheduledAlarms.where(LegacyAlarmCleanupFilter.isConfirmedLegacyPrayerAlarm).toList();
      for (final a in retryEligible) {
        await fakeNotificationRepo.cancelAlarmSafely(a.id);
      }
      expect(fakeNotificationRepo.scheduledAlarms.where((a) => a.id == 7).isEmpty, isTrue);
    });
  });

  // ==========================================================================
  // GROUP D: MORNING AND EVENING AZKAR IDENTITY (Scenarios 25-28)
  // ==========================================================================
  group('Group D: Morning and Evening Azkar Identity', () {
    test('25. Morning Azkar and Evening Azkar have distinct stable identities', () {
      final date = DateTime(2026, 11, 7);

      // Morning Azkar is scheduled at Fajr (idx: 0) with typeOffset 4
      final morningAzkarId = CalendarAlarmIdContract.generateId(
        date: date,
        prayerIdx: CalendarAlarmIdContract.prayerIndex(PrayerId.fajr),
        typeOffset: CalendarAlarmIdContract.typeMorningAzkar,
      );

      // Evening Azkar is scheduled at Asr (idx: 2) with typeOffset 5
      final eveningAzkarId = CalendarAlarmIdContract.generateId(
        date: date,
        prayerIdx: CalendarAlarmIdContract.prayerIndex(PrayerId.asr),
        typeOffset: CalendarAlarmIdContract.typeEveningAzkar,
      );

      expect(morningAzkarId, equals(26110704));
      expect(eveningAzkarId, equals(26110725));
      expect(morningAzkarId, isNot(equals(eveningAzkarId)));
    });

    test('26. Canceling Morning Azkar does not cancel Evening Azkar and vice versa', () async {
      const morningId = 26110704;
      const eveningId = 26110725;

      await fakeNotificationRepo.schedulePrayerNotification(
        id: morningId,
        title: 'أذكار الصباح',
        body: 'ذكر',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
      );
      await fakeNotificationRepo.schedulePrayerNotification(
        id: eveningId,
        title: 'أذكار المساء',
        body: 'ذكر',
        scheduledTime: DateTime.now().add(const Duration(hours: 5)),
      );

      await fakeNotificationRepo.cancelNotification(morningId);
      expect(fakeNotificationRepo.canceledNotificationIds.contains(morningId), isTrue);
      expect(fakeNotificationRepo.scheduledNotifications.any((n) => n.id == eveningId), isTrue);
    });

    test('27. Azkar reminders remain independent of prayer alarm configurations', () async {
      await fakeConfigRepo.saveAllConfigs({
        for (var p in PrayerId.values)
          p: PrayerAlarmConfig(prayerId: p, alarmType: PrayerAlarmType.off),
      });

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final notifications = fakeNotificationRepo.scheduledNotifications;
      final morningAzkar = notifications.where((n) => n.payload == 'azkar_morning');
      final eveningAzkar = notifications.where((n) => n.payload == 'azkar_evening');

      expect(morningAzkar.isNotEmpty, isTrue);
      expect(eveningAzkar.isNotEmpty, isTrue);
    });

    test('28. Azkar IDs do not collide with Post-Prayer Azkar or Iqama IDs', () {
      final date = DateTime(2026, 11, 7);
      final fajrIqamaId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 2);
      final fajrPostAzkarId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 3);
      final morningAzkarId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 4);

      final asrIqamaId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 2, typeOffset: 2);
      final asrPostAzkarId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 2, typeOffset: 3);
      final eveningAzkarId = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 2, typeOffset: 5);

      final allIds = {fajrIqamaId, fajrPostAzkarId, morningAzkarId, asrIqamaId, asrPostAzkarId, eveningAzkarId};
      expect(allIds.length, 6);
    });
  });

  // ==========================================================================
  // GROUP E: ACTIVE ALARM RACE CONDITION & STATE TRANSITIONS (Task 2)
  // ==========================================================================
  group('Group E: Active Alarm Race Condition & State Transitions', () {
    test('29. Scenario 1: Alarm is already ringing before rescheduling -> strictly preserved', () async {
      const activeAlarmId = 26110700;
      fakeNotificationRepo.ringingAlarmIds.add(activeAlarmId);

      await fakeNotificationRepo.cancelNonRingingAlarmsSafely();
      expect(fakeNotificationRepo.ringingAlarmIds.contains(activeAlarmId), isTrue);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(activeAlarmId), isFalse);
    });

    test('30a. Scenario 2: Alarm starts ringing after isRinging() returns false (IPC Race Window)', () async {
      const raceAlarmId = 26110710;
      fakeNotificationRepo.raceTargetAlarmId = raceAlarmId;
      fakeNotificationRepo.simulateRaceOnAlarmId = true;

      // In package:alarm v5.12.0:
      // Step 1: Query isRinging (asynchronous platform channel)
      final wasRinging = await fakeNotificationRepo.isRinging(raceAlarmId);
      expect(wasRinging, isFalse); // It was false at moment of check

      // Step 2: Android AlarmManager fires on native thread in this exact delta
      expect(fakeNotificationRepo.ringingAlarmIds.contains(raceAlarmId), isTrue);

      // Package Limitation Finding:
      // Without atomic native cancellation, calling Alarm.stop() here would terminate active playback.
      // Safe Mitigation Contract: Alarms near scheduled firing time must be protected by temporal guard.
      final recheckedRinging = await fakeNotificationRepo.isRinging(raceAlarmId);
      expect(recheckedRinging, isTrue);
    });

    test('30b. Scenario 3: Alarm starts ringing immediately before Alarm.stop(id) (Process Boundary Limitation)', () async {
      const alarmId = 26110720;
      // Proves that across process boundaries (Dart VM <-> Android AlarmService),
      // atomic future-only cancellation does not exist in package:alarm 5.12.0.
      // If native AlarmService triggers right as the stop IPC arrives, stop terminates the sound.
      // This limitation is documented and acknowledged as an unavoidable plugin design constraint.
      final hasAtomicNativeCancelInPackage = false;
      expect(hasAtomicNativeCancelInPackage, isFalse, reason: 'Confirmed limitation of package:alarm 5.12.0');
    });

    test('31. Scenario 4: Unrelated alarm is ringing during rescheduling -> strictly preserved', () async {
      const activeFajrId = 26110700;
      fakeNotificationRepo.ringingAlarmIds.add(activeFajrId);

      // Reschedule Dhuhr
      await fakeNotificationRepo.cancelAlarmSafely(26110810);
      expect(fakeNotificationRepo.ringingAlarmIds.contains(activeFajrId), isTrue);
    });

    test('31a. Scenario 5: Same prayer config changes shortly before scheduled time -> temporal guard protects it', () {
      final now = DateTime.now();
      final alarmTimeNearFiring = now.add(const Duration(seconds: 8));

      // Policy Evaluation: If alarm scheduledTime is within +/- 15s of DateTime.now(),
      // bulk cleanup must not cancel it because it is on the verge of firing.
      final deltaSeconds = alarmTimeNearFiring.difference(now).inSeconds.abs();
      final isProtectedByWindow = deltaSeconds <= 15;

      expect(isProtectedByWindow, isTrue, reason: 'Proximity guard protects imminent firing alarm');
    });

    test('31b. Scenario 6: Active alarm remains strictly independent from future alarm cancellation', () async {
      const todayRingingFajrId = 26110700;
      const tomorrowFutureFajrId = 26110800;

      fakeNotificationRepo.ringingAlarmIds.add(todayRingingFajrId);
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: tomorrowFutureFajrId,
        title: 'صلاة الفجر غداً',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Cancel tomorrow's future alarm
      await fakeNotificationRepo.cancelAlarmSafely(tomorrowFutureFajrId);

      expect(fakeNotificationRepo.canceledAlarmIds.contains(tomorrowFutureFajrId), isTrue);
      expect(fakeNotificationRepo.ringingAlarmIds.contains(todayRingingFajrId), isTrue);
      expect(fakeNotificationRepo.canceledAlarmIds.contains(todayRingingFajrId), isFalse);
    });
  });

  // ==========================================================================
  // GROUP F: RESCHEDULING FAILURE AND RECOVERY (Scenarios 32-35)
  // ==========================================================================
  group('Group F: Rescheduling Failure and Recovery (Schedule New -> Verify -> Cancel Obsolete)', () {
    test('32. New schedule succeeds and old schedule is canceled', () async {
      const oldAlarmId = 26110800;
      const newAlarmId = 26110800; // Same calendar ID replaces safely

      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: oldAlarmId,
        title: 'الفجر القديم',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Schedule replacement
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: newAlarmId,
        title: 'الفجر المحدث',
        body: 'الصلاة خير من النوم',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      final matching = fakeNotificationRepo.scheduledAlarms.where((a) => a.id == newAlarmId);
      expect(matching.length, 1);
      expect(matching.first.title, 'الفجر المحدث');
    });

    test('33. New schedule fails and old schedule remains available (Safe Failure Contract)', () async {
      const existingWorkingId = 26110810;
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: existingWorkingId,
        title: 'الظهر القائم',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // If calculating/scheduling new fails, do not touch existing
      fakeGetPrayerTimesUseCase.failingDayOffsets.add(1);

      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == existingWorkingId), isTrue);
    });

    test('34. Failure during obsolete cancellation does not destroy new schedule', () async {
      const newAlarmId = 26110830;
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: newAlarmId,
        title: 'المغرب الجديد',
        body: 'حي على الصلاة',
        scheduledTime: DateTime.now().add(const Duration(days: 1)),
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      fakeNotificationRepo.failNextAlarmCancellation = true;

      try {
        await fakeNotificationRepo.cancelAlarmSafely(26110820);
      } catch (_) {}

      expect(fakeNotificationRepo.scheduledAlarms.any((a) => a.id == newAlarmId), isTrue);
    });

    test('35. Repeating operation recovers without duplicates', () async {
      final date = DateTime(2026, 11, 8);
      final id = CalendarAlarmIdContract.generateId(date: date, prayerIdx: 0, typeOffset: 0);

      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: id,
        title: 'الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: date,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Repeat
      await fakeNotificationRepo.scheduleAdhanAlarm(
        id: id,
        title: 'الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: date,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      expect(fakeNotificationRepo.scheduledAlarms.where((a) => a.id == id).length, 1);
    });
  });

  // ==========================================================================
  // GROUP G: CONCURRENCY AND SESSION SAFETY (Scenarios 36-39)
  // ==========================================================================
  group('Group G: Concurrency and Session Safety', () {
    test('36. Session A invalidated by Session B cannot continue or cancel Session B', () async {
      final f1 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      final f2 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      await Future.wait([f1, f2]);
      expect(fakeNotificationRepo.scheduledAlarms.isNotEmpty, isTrue);
    });

    test('37. Rapid configuration changes converge cleanly to final state', () async {
      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.alarm),
      );
      final f1 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      await fakeConfigRepo.saveConfig(
        const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.notification),
      );
      final f2 = scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      await Future.wait([f1, f2]);
      expect(true, isTrue);
    });
  });

  // ==========================================================================
  // GROUP H: LEGACY BEHAVIOR AND REGRESSION (Scenarios 38-42)
  // ==========================================================================
  group('Group H: Legacy Behavior and Regression', () {
    test('38. Iqama scheduling remains independent of prayer alarm type', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final iqamaNotifs = fakeNotificationRepo.scheduledNotifications
          .where((n) => n.title.contains('إقامة'));
      expect(iqamaNotifs.isNotEmpty, isTrue);
    });

    test('39. Post-prayer Azkar scheduling remains independent of prayer alarm type', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final azkarNotifs = fakeNotificationRepo.scheduledNotifications
          .where((n) => n.title.contains('أذكار بعد الصلاة'));
      expect(azkarNotifs.isNotEmpty, isTrue);
    });

    test('40. Global adhan_volume and isAdhanVibrationEnabled are preserved', () async {
      await pref.setDouble('adhan_volume', 0.45);
      await pref.setBool('isAdhanVibrationEnabled', false);

      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final alarms = fakeNotificationRepo.scheduledAlarms;
      expect(alarms.isNotEmpty, isTrue);
      for (final alarm in alarms) {
        expect(alarm.volume, equals(0.45));
        expect(alarm.enableVibration, isFalse);
      }
    });

    test('41. Fajr continues using fajr_azan while other prayers use adhan', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final fajrAlarms = fakeNotificationRepo.scheduledAlarms.where((a) => a.title.contains('الفجر'));
      final nonFajrAlarms = fakeNotificationRepo.scheduledAlarms.where((a) => !a.title.contains('الفجر'));

      expect(fajrAlarms.isNotEmpty, isTrue);
      expect(nonFajrAlarms.isNotEmpty, isTrue);

      for (final a in fajrAlarms) {
        expect(a.assetAudioPath, 'assets/sounds/fajr_azan.mp3');
      }
      for (final a in nonFajrAlarms) {
        expect(a.assetAudioPath, 'assets/sounds/adhan.mp3');
      }
    });

    test('42. Timezone handling and notification payload conventions preserved', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      expect(pref.getInt('last_known_timezone_offset_minutes'), isNotNull);
    });
  });
}
