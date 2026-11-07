import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';

/// Recorded call to [scheduleAdhanAlarm]
class RecordedAlarmCall {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String assetAudioPath;
  final double? volume;
  final bool enableVibration;

  RecordedAlarmCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    required this.assetAudioPath,
    this.volume,
    required this.enableVibration,
  });
}

/// Recorded call to [schedulePrayerNotification]
class RecordedNotificationCall {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String? soundName;
  final String? payload;

  RecordedNotificationCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    this.soundName,
    this.payload,
  });
}

/// Fake notification repository that records all scheduling & cancellation calls.
class FakeNotificationRepository implements BaseNotificationRepository {
  final List<RecordedAlarmCall> scheduledAlarms = [];
  final List<RecordedNotificationCall> scheduledNotifications = [];
  int cancelAllAlarmsCallCount = 0;
  int cancelActivePrayerNotificationCallCount = 0;
  int cancelAllNotificationsCallCount = 0;
  final List<int> cancelledNotificationIds = [];

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
    scheduledAlarms.add(
      RecordedAlarmCall(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        assetAudioPath: assetAudioPath,
        volume: volume,
        enableVibration: enableVibration,
      ),
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
    scheduledNotifications.add(
      RecordedNotificationCall(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        soundName: soundName,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancelAllAlarms() async {
    cancelAllAlarmsCallCount++;
  }

  @override
  Future<void> cancelActivePrayerNotification() async {
    cancelActivePrayerNotificationCallCount++;
  }

  @override
  Future<void> cancelAllNotifications() async {
    cancelAllNotificationsCallCount++;
  }

  @override
  Future<void> cancelNotification(int id) async {
    cancelledNotificationIds.add(id);
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
}

/// Fake GetPrayerTimesUseCase that returns deterministic future prayer times for any requested date.
class FakeGetPrayerTimesUseCase implements GetPrayerTimesUseCase {
  final List<DateTime> requestedDates = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Either<Failure, PrayerTimesEntity>> call({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    requestedDates.add(date);

    // Build future prayer times anchored on the given day (e.g., at hours 4, 6, 12, 15, 18, 20)
    // To ensure they are in the future for testing, we use date + fixed future hours.
    final base = DateTime(date.year, date.month, date.day);
    return Right(
      PrayerTimesEntity(
        fajr: base.add(const Duration(hours: 4, minutes: 30)),
        sunrise: base.add(const Duration(hours: 6, minutes: 0)),
        dhuhr: base.add(const Duration(hours: 12, minutes: 15)),
        asr: base.add(const Duration(hours: 15, minutes: 30)),
        maghrib: base.add(const Duration(hours: 18, minutes: 0)),
        isha: base.add(const Duration(hours: 19, minutes: 30)),
      ),
    );
  }
}

/// Fake GetIqamaDelaysUseCase returning empty delays to isolate prayer adhans.
class FakeGetIqamaDelaysUseCase implements GetIqamaDelaysUseCase {
  final Map<String, int> delays;
  FakeGetIqamaDelaysUseCase([this.delays = const {}]);

  @override
  Future<Map<String, int>> execute() async => delays;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationRepository fakeRepo;
  late FakeGetPrayerTimesUseCase fakeGetPrayerTimes;
  late FakeGetIqamaDelaysUseCase fakeGetIqamaDelays;
  late CancelAllNotificationsUseCase cancelAllUseCase;
  late SchedulePrayerUseCase schedulePrayerUseCase;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    fakeRepo = FakeNotificationRepository();
    fakeGetPrayerTimes = FakeGetPrayerTimesUseCase();
    fakeGetIqamaDelays = FakeGetIqamaDelaysUseCase();
    cancelAllUseCase = CancelAllNotificationsUseCase(fakeRepo);
    schedulePrayerUseCase = SchedulePrayerUseCase(fakeRepo);
  });

  ScheduleWeeklyPrayersUseCase createScheduler() {
    return ScheduleWeeklyPrayersUseCase(
      getPrayerTimesUseCase: fakeGetPrayerTimes,
      cancelAllNotificationsUseCase: cancelAllUseCase,
      schedulePrayerUseCase: schedulePrayerUseCase,
      getIqamaDelaysUseCase: fakeGetIqamaDelays,
      notificationRepository: fakeRepo,
      pref: prefs,
    );
  }

  group('P4.1-B — Legacy Characterization Tests (Existing adhanStyle behavior)', () {
    test('Global Alarm Mode (adhanStyle = alarm) schedules 5 full-screen alarms per future day', () async {
      await prefs.setString('adhanStyle', 'alarm');
      await prefs.setDouble('adhan_volume', 0.85);
      await prefs.setBool('isAdhanVibrationEnabled', true);
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();
      // Future times ensure all 5 prayers per day are scheduled
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      // 1. Initial cleanup was called
      expect(fakeRepo.cancelAllAlarmsCallCount, equals(1));
      expect(fakeRepo.cancelActivePrayerNotificationCallCount, equals(1));

      // 2. Verified 5-day horizon (days 0, 1, 2, 3, 4)
      expect(fakeGetPrayerTimes.requestedDates.length, equals(5));

      // 3. For days 1..4 (which are fully in the future), 5 prayers per day = 20 alarms minimum
      expect(fakeRepo.scheduledAlarms.length, greaterThanOrEqualTo(20));
      expect(fakeRepo.scheduledNotifications, isEmpty); // No notification-style adhans

      // 4. Check Fajr vs Non-Fajr audio paths
      final fajrAlarms = fakeRepo.scheduledAlarms.where((a) => a.title.contains('الفجر')).toList();
      final nonFajrAlarms = fakeRepo.scheduledAlarms.where((a) => !a.title.contains('الفجر')).toList();

      expect(fajrAlarms, isNotEmpty);
      expect(nonFajrAlarms, isNotEmpty);

      for (final alarm in fajrAlarms) {
        expect(alarm.assetAudioPath, equals('assets/sounds/fajr_azan.mp3'));
        expect(alarm.body, equals('الصلاة خير من النوم'));
        expect(alarm.volume, equals(0.85));
        expect(alarm.enableVibration, isTrue);
      }

      for (final alarm in nonFajrAlarms) {
        expect(alarm.assetAudioPath, equals('assets/sounds/adhan.mp3'));
        expect(alarm.body, equals('حي على الصلاة، حي على الفلاح'));
        expect(alarm.volume, equals(0.85));
        expect(alarm.enableVibration, isTrue);
      }
    });

    test('Global Notification Mode (adhanStyle = notification) schedules simple notifications only', () async {
      await prefs.setString('adhanStyle', 'notification');
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      // 1. Initial cleanup called
      expect(fakeRepo.cancelAllAlarmsCallCount, equals(1));
      expect(fakeRepo.cancelActivePrayerNotificationCallCount, equals(1));

      // 2. No full-screen alarms scheduled
      expect(fakeRepo.scheduledAlarms, isEmpty);

      // 3. Simple notifications scheduled
      expect(fakeRepo.scheduledNotifications.length, greaterThanOrEqualTo(20));

      // 4. Verify soundName for Fajr vs others
      final fajrNotifs = fakeRepo.scheduledNotifications.where((n) => n.title.contains('الفجر')).toList();
      final otherNotifs = fakeRepo.scheduledNotifications.where((n) => !n.title.contains('الفجر')).toList();

      for (final notif in fajrNotifs) {
        expect(notif.soundName, equals('fajr_azan'));
        expect(notif.payload, equals('adhan_simple_fajr'));
      }

      for (final notif in otherNotifs) {
        expect(notif.soundName, equals('adhan'));
        expect(notif.payload, startsWith('adhan_simple_'));
      }
    });

    test('Global Disabled Mode (adhanStyle = none) schedules no prayer alarms or adhan notifications', () async {
      await prefs.setString('adhanStyle', 'none');
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      // 1. Initial cleanup still called
      expect(fakeRepo.cancelAllAlarmsCallCount, equals(1));
      expect(fakeRepo.cancelActivePrayerNotificationCallCount, equals(1));

      // 2. Zero alarms and zero notifications scheduled
      expect(fakeRepo.scheduledAlarms, isEmpty);
      expect(fakeRepo.scheduledNotifications, isEmpty);

      // 3. scheduled_until_date is still marked completed
      expect(prefs.getString('scheduled_until_date'), isNotNull);
    });

    test('Missing adhanStyle defaults to alarm mode (legacy backward-compatibility contract)', () async {
      // Do NOT set adhanStyle
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      // Legacy fallback in code: `pref.getString('adhanStyle') ?? 'alarm'`
      expect(fakeRepo.scheduledAlarms.length, greaterThanOrEqualTo(20));
      expect(fakeRepo.scheduledNotifications, isEmpty);
    });

    test('Alarm IDs are sequential integers starting at 1', () async {
      await prefs.setString('adhanStyle', 'alarm');
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();
      await scheduler.execute(30.0444, 31.2357, 'Cairo', 'EG');

      final ids = fakeRepo.scheduledAlarms.map((a) => a.id).toList();
      expect(ids.first, equals(1));
      for (int i = 0; i < ids.length - 1; i++) {
        expect(ids[i + 1], equals(ids[i] + 1), reason: 'IDs must increment sequentially');
      }
    });

    test('Concurrent sessions: newer session invalidates and cancels older session work', () async {
      await prefs.setString('adhanStyle', 'alarm');
      await prefs.setBool('isIqamaEnabled', false);
      await prefs.setBool('isAzkarReminderEnabled', false);

      final scheduler = createScheduler();

      // Launch session 1 and session 2 back-to-back
      final future1 = scheduler.execute(30.0444, 31.2357, 'Cairo');
      final future2 = scheduler.execute(30.0444, 31.2357, 'Cairo');

      await Future.wait([future1, future2]);

      // cancelAllAlarms is called by both sessions (at start of each)
      expect(fakeRepo.cancelAllAlarmsCallCount, equals(2));
      // scheduled_until_date is successfully updated by the winning session
      expect(prefs.getString('scheduled_until_date'), isNotNull);
    });
  });
}

