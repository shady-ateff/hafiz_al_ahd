import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test Spy for BasePrayerAlarmConfigRepository with granular control over getConfigs behavior.
class SpyingPrayerAlarmConfigRepository implements BasePrayerAlarmConfigRepository {
  Map<PrayerId, PrayerAlarmConfig>? configs;
  Exception? exceptionToThrow;
  int getConfigsCallCount = 0;

  SpyingPrayerAlarmConfigRepository({
    this.configs,
    this.exceptionToThrow,
  }) {
    configs ??= {
      PrayerId.fajr: const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
      PrayerId.dhuhr: const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.alarm),
      PrayerId.asr: const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.alarm),
      PrayerId.maghrib: const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.alarm),
      PrayerId.isha: const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.alarm),
    };
  }

  @override
  Future<Map<PrayerId, PrayerAlarmConfig>> getConfigs() async {
    getConfigsCallCount++;
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return configs != null ? Map.from(configs!) : <PrayerId, PrayerAlarmConfig>{};
  }

  @override
  Future<PrayerAlarmConfig> getConfig(PrayerId prayerId) async => configs![prayerId]!;

  @override
  Future<void> saveConfig(PrayerAlarmConfig config) async {
    configs![config.prayerId] = config;
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

/// Test Spy for BaseNotificationRepository using Fake to verify zero side-effects.
class SpyingNotificationRepository extends Fake implements BaseNotificationRepository {
  int cancelAllAlarmsCalls = 0;
  int cancelActivePrayerNotificationCalls = 0;
  final List<int> scheduledAlarmIds = [];
  final List<int> scheduledNotificationIds = [];
  final List<int> cancelledNotificationIds = [];
  final List<int> cancelledAlarmSafelyIds = [];

  @override
  Future<void> cancelNotification(int id) async {
    cancelledNotificationIds.add(id);
  }

  @override
  Future<EventCancellationStatus> cancelAlarmSafely(
    int id, {
    DateTime? expectedScheduledTime,
    String? expectedAssetAudioPath,
  }) async {
    cancelledAlarmSafelyIds.add(id);
    return EventCancellationStatus.cancelled;
  }

  @override
  Future<EventCancellationStatus> cancelNotificationSafely(int id) async {
    cancelledNotificationIds.add(id);
    return EventCancellationStatus.cancelled;
  }

  @override
  Future<EventVerificationStatus> verifyAlarm({
    required int id,
    required DateTime expectedScheduledTime,
    String? expectedAssetAudioPath,
    double? expectedVolume,
    bool? expectedEnableVibration,
  }) async {
    return scheduledAlarmIds.contains(id)
        ? EventVerificationStatus.matching
        : EventVerificationStatus.absent;
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
    return scheduledNotificationIds.contains(id)
        ? EventVerificationStatus.matching
        : EventVerificationStatus.absent;
  }

  @override
  Future<void> cancelAllAlarms() async {
    cancelAllAlarmsCalls++;
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    cancelActivePrayerNotificationCalls++;
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
    bool androidFullScreenIntent = true,
    String? stopButton = 'إيقاف الأذان',
  }) async {
    scheduledAlarmIds.add(id);
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
    scheduledNotificationIds.add(id);
  }
}

class FakePrayerTimesUseCase extends Fake implements GetPrayerTimesUseCase {
  @override
  Future<Either<Failure, PrayerTimesEntity>> call({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences pref;
  late SpyingPrayerAlarmConfigRepository spyConfigRepo;
  late SpyingNotificationRepository spyNotificationRepo;
  late FakePrayerTimesUseCase fakePrayerTimesUseCase;
  late FakeIqamaDelaysUseCase fakeIqamaDelaysUseCase;
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

    spyConfigRepo = SpyingPrayerAlarmConfigRepository();
    spyNotificationRepo = SpyingNotificationRepository();
    fakePrayerTimesUseCase = FakePrayerTimesUseCase();
    fakeIqamaDelaysUseCase = FakeIqamaDelaysUseCase();

    scheduler = ScheduleWeeklyPrayersUseCase(
      getPrayerTimesUseCase: fakePrayerTimesUseCase,
      cancelAllNotificationsUseCase: CancelAllNotificationsUseCase(spyNotificationRepo),
      schedulePrayerUseCase: SchedulePrayerUseCase(spyNotificationRepo),
      getIqamaDelaysUseCase: fakeIqamaDelaysUseCase,
      notificationRepository: spyNotificationRepo,
      pref: pref,
      prayerAlarmConfigRepository: spyConfigRepo,
    );
  });

  // ============================================================================
  // TEST GROUP A: SUCCESSFUL READS
  // ============================================================================
  group('Test Group A: Successful Reads', () {
    test('1. Reading 5 valid configurations succeeds', () async {
      await expectLater(
        scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        completes,
      );
    });

    test('2. getConfigs() is called exactly once per scheduler execution', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      expect(spyConfigRepo.getConfigsCallCount, equals(1));
    });

    test('3. Valid configurations allow modern scheduling path to complete without blanket sweep', () async {
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      expect(spyNotificationRepo.cancelAllAlarmsCalls, equals(0));
      expect(spyNotificationRepo.cancelActivePrayerNotificationCalls, equals(0));
      expect(pref.getString('scheduled_until_date'), isNotNull);
    });
  });

  // ============================================================================
  // TEST GROUP B: MISSING CONFIGURATIONS
  // ============================================================================
  group('Test Group B: Missing Configurations', () {
    test('4. Empty configurations map throws StateError', () async {
      spyConfigRepo.configs = {};
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Incomplete or invalid'))),
      );
    });

    test('5. Missing Fajr throws StateError', () async {
      spyConfigRepo.configs!.remove(PrayerId.fajr);
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>()),
      );
    });

    test('6. Missing Dhuhr throws StateError', () async {
      spyConfigRepo.configs!.remove(PrayerId.dhuhr);
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>()),
      );
    });

    test('7. Missing Asr throws StateError', () async {
      spyConfigRepo.configs!.remove(PrayerId.asr);
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>()),
      );
    });

    test('8. Missing Maghrib throws StateError', () async {
      spyConfigRepo.configs!.remove(PrayerId.maghrib);
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>()),
      );
    });

    test('9. Missing Isha throws StateError', () async {
      spyConfigRepo.configs!.remove(PrayerId.isha);
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ============================================================================
  // TEST GROUP C: DUPLICATE / INCONSISTENT CONFIGURATIONS
  // ============================================================================
  group('Test Group C: Duplicate & Inconsistent Configurations', () {
    test('10. Mismatched PrayerId (key indicates fajr, but entity holds dhuhr) throws StateError', () async {
      spyConfigRepo.configs![PrayerId.fajr] = const PrayerAlarmConfig(
        prayerId: PrayerId.dhuhr,
        alarmType: PrayerAlarmType.alarm,
      );
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Mismatched PrayerId'))),
      );
    });
  });

  // ============================================================================
  // TEST GROUP D: REPOSITORY FAILURE
  // ============================================================================
  group('Test Group D: Repository Failure', () {
    test('11. Repository throws Exception: Exception propagates without being swallowed', () async {
      spyConfigRepo.exceptionToThrow = Exception('Database disk I/O error');
      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'toString', contains('Database disk I/O error'))),
      );
    });

    test('12. Scheduling immediately aborts after Repository throws Exception', () async {
      spyConfigRepo.exceptionToThrow = Exception('Simulated fatal crash during read');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}
      expect(pref.getString('scheduled_until_date'), isNull);
    });
  });

  // ============================================================================
  // TEST GROUP E: SIDE-EFFECT ISOLATION (ZERO SIDE-EFFECTS ON FAILURE)
  // ============================================================================
  group('Test Group E: Side-Effect Isolation (Zero Side-Effects on Failure)', () {
    test('13. When getConfigs() throws: cancelAllAlarms is NOT called', () async {
      spyConfigRepo.exceptionToThrow = Exception('Config read failed');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}
      expect(spyNotificationRepo.cancelAllAlarmsCalls, equals(0));
    });

    test('14. When getConfigs() throws: cancelActivePrayerNotification is NOT called', () async {
      spyConfigRepo.exceptionToThrow = Exception('Config read failed');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}
      expect(spyNotificationRepo.cancelActivePrayerNotificationCalls, equals(0));
    });

    test('15. When getConfigs() throws: scheduleAdhanAlarm is NOT called', () async {
      spyConfigRepo.exceptionToThrow = Exception('Config read failed');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}
      expect(spyNotificationRepo.scheduledAlarmIds, isEmpty);
    });

    test('16. When getConfigs() throws: schedulePrayerNotification is NOT called', () async {
      spyConfigRepo.exceptionToThrow = Exception('Config read failed');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}
      expect(spyNotificationRepo.scheduledNotificationIds, isEmpty);
    });

    test('17. When getConfigs() throws: scheduled_until_date is untouched', () async {
      const existingDate = '2026-11-05T12:00:00.000';
      await pref.setString('scheduled_until_date', existingDate);

      spyConfigRepo.exceptionToThrow = Exception('Config read failed');
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}

      expect(pref.getString('scheduled_until_date'), equals(existingDate));
    });

    test('18. When validation fails: session ID is NOT incremented (previous session not invalidated)', () async {
      // First, run a successful session to establish a session ID
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      final sessionIdAfterSuccess = ScheduleWeeklyPrayersUseCase.currentSessionId;
      expect(sessionIdAfterSuccess, greaterThan(0));

      // Now induce validation failure
      spyConfigRepo.configs!.remove(PrayerId.fajr);
      try {
        await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');
      } catch (_) {}

      // Session ID must remain strictly unchanged!
      expect(ScheduleWeeklyPrayersUseCase.currentSessionId, equals(sessionIdAfterSuccess));
    });

    test('19. When getConfigs() fails: does NOT silently fallback to adhanStyle', () async {
      // adhanStyle is set to 'notification'
      await pref.setString('adhanStyle', 'notification');
      spyConfigRepo.exceptionToThrow = Exception('Config failure');

      await expectLater(
        () => scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG'),
        throwsA(isA<Exception>()),
      );
      // Ensure no fallback notifications were scheduled!
      expect(spyNotificationRepo.scheduledNotificationIds, isEmpty);
      expect(spyNotificationRepo.scheduledAlarmIds, isEmpty);
    });
  });
}
