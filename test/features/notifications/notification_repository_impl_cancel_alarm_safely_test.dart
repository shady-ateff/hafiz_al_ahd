import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/schedule_operation_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationRepositoryImpl repository;
  bool isRingingMockValue = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    isRingingMockValue = false;

    // Register mock Pigeon binary message handlers for package:alarm
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.alarm.AlarmApi.setAlarm', (ByteData? message) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.alarm.AlarmApi.stopAlarm', (ByteData? message) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.alarm.AlarmApi.stopAll', (ByteData? message) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.alarm.AlarmApi.isRinging', (ByteData? message) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[isRingingMockValue]);
    });

    await Alarm.init();
    repository = NotificationRepositoryImpl();
  });

  tearDown(() async {
    await Alarm.stopAll();
  });

  group('NotificationRepositoryImpl.cancelAlarmSafely — Production Contract Tests', () {
    test('1. Absent alarm returns alreadyAbsent (idempotent success without package side-effects)', () async {
      const validId = 26110810; // Dhuhr modern ID
      final result = await repository.cancelAlarmSafely(validId);
      expect(result, EventCancellationStatus.alreadyAbsent);
      expect(result.isSuccessful, isTrue);
    });

    test('2. ID outside prayer range is rejected with failed (Fail-Closed)', () async {
      // Negative ID
      expect(await repository.cancelAlarmSafely(-1), EventCancellationStatus.failed);
      // Zero ID
      expect(await repository.cancelAlarmSafely(0), EventCancellationStatus.failed);
      // Between legacy range (100) and modern range (24010100)
      expect(await repository.cancelAlarmSafely(101), EventCancellationStatus.failed);
      expect(await repository.cancelAlarmSafely(888), EventCancellationStatus.failed, reason: 'Reserved test alarm ID 888 is protected');
      expect(await repository.cancelAlarmSafely(999), EventCancellationStatus.failed, reason: 'Reserved widget ID 999 is protected');
      expect(await repository.cancelAlarmSafely(8888), EventCancellationStatus.failed, reason: 'Reserved reminder ID 8888 is protected');
      expect(await repository.cancelAlarmSafely(1000), EventCancellationStatus.failed);
      // Beyond 2099 boundary
      expect(await repository.cancelAlarmSafely(100000000), EventCancellationStatus.failed);
    });

    test('3. Valid owned future alarm is stopped and verified absent', () async {
      const alarmId = 26110810;
      final futureTime = DateTime.now().add(const Duration(hours: 3));

      await repository.scheduleAdhanAlarm(
        id: alarmId,
        title: 'صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: futureTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Verify alarm exists before cancellation
      final alarmBefore = await Alarm.getAlarm(alarmId);
      expect(alarmBefore, isNotNull);

      // Cancel safely
      final result = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.cancelled);
      expect(result.isSuccessful, isTrue);
      final alarmAfter = await Alarm.getAlarm(alarmId);
      expect(alarmAfter, isNull, reason: 'Alarm must be absent in package registry after cancellation');
    });

    test('4. Unrecognized audio asset is rejected with failed (Fail-Closed, zero side-effects)', () async {
      const alarmId = 26110810;
      final futureTime = DateTime.now().add(const Duration(hours: 3));

      // Schedule alarm with an external/unrecognized sound
      final settings = AlarmSettings(
        id: alarmId,
        dateTime: futureTime,
        assetAudioPath: 'assets/sounds/unrecognized_bell.mp3',
        volumeSettings: VolumeSettings.fade(
          volume: 1.0,
          fadeDuration: const Duration(seconds: 1),
          volumeEnforced: false,
        ),
        notificationSettings: const NotificationSettings(
          title: 'تنبيه خارجي',
          body: 'تنبيه',
        ),
      );
      await Alarm.set(alarmSettings: settings);

      final result = await repository.cancelAlarmSafely(alarmId);
      expect(result, EventCancellationStatus.failed, reason: 'Unrecognized sound asset must Fail-Closed');

      // Alarm must remain intact
      final alarmAfter = await Alarm.getAlarm(alarmId);
      expect(alarmAfter, isNotNull, reason: 'Unowned alarm must not be canceled');
    });

    test('5. Mismatched expected asset audio path returns failed (Fail-Closed)', () async {
      const alarmId = 26110800; // Fajr
      final futureTime = DateTime.now().add(const Duration(hours: 5));

      await repository.scheduleAdhanAlarm(
        id: alarmId,
        title: 'صلاة الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: futureTime,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      // Caller expects general adhan, but alarm on device has fajr_azan
      final result = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.failed, reason: 'Asset path mismatch must reject cancellation');
      expect(await Alarm.getAlarm(alarmId), isNotNull, reason: 'Alarm must not be touched');
    });

    test('6. Expected scheduled time drift > 60s returns failed (Fail-Closed)', () async {
      const alarmId = 26110810;
      final actualTime = DateTime.now().add(const Duration(hours: 3));
      final discrepantExpectedTime = actualTime.add(const Duration(minutes: 5));

      await repository.scheduleAdhanAlarm(
        id: alarmId,
        title: 'صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: actualTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      final result = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: discrepantExpectedTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.failed, reason: 'Time drift > 60s must reject cancellation');
      expect(await Alarm.getAlarm(alarmId), isNotNull);
    });

    test('7. Temporal guard (+/- 15s) suppresses cancellation to protect imminent alarm firing', () async {
      const alarmId = 26110810;
      // Scheduled within 10 seconds from now
      final imminentTime = DateTime.now().add(const Duration(seconds: 10));

      final settings = AlarmSettings(
        id: alarmId,
        dateTime: imminentTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
        volumeSettings: VolumeSettings.fade(
          volume: 1.0,
          fadeDuration: const Duration(seconds: 1),
          volumeEnforced: false,
        ),
        notificationSettings: const NotificationSettings(
          title: 'صلاة الظهر',
          body: 'حي على الصلاة',
        ),
      );
      await Alarm.set(alarmSettings: settings);

      final result = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: imminentTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.deferredImminent, reason: 'Imminent firing alarm (<= 15s) must be protected');
      expect(result.isDeferred, isTrue);
      expect(await Alarm.getAlarm(alarmId), isNotNull, reason: 'Alarm must remain scheduled');
    });

    test('8. Actively ringing alarm suppresses cancellation (Audio Protection Contract)', () async {
      const alarmId = 26110810;
      final futureTime = DateTime.now().add(const Duration(hours: 2));

      await repository.scheduleAdhanAlarm(
        id: alarmId,
        title: 'صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: futureTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Simulate alarm actively ringing
      isRingingMockValue = true;

      final result = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.deferredRinging, reason: 'Actively ringing alarm cancellation must be suppressed');
      expect(result.isDeferred, isTrue);
      // The alarm must not be canceled
      expect(await Alarm.getAlarm(alarmId), isNotNull);
    });

    test('9. Confirmed legacy prayer alarm (ID 1..100) is eligible and canceled safely', () async {
      const legacyId = 1;
      final futureTime = DateTime.now().add(const Duration(hours: 4));

      await repository.scheduleAdhanAlarm(
        id: legacyId,
        title: 'حان الآن موعد صلاة الفجر',
        body: 'الصلاة خير من النوم',
        scheduledTime: futureTime,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      final result = await repository.cancelAlarmSafely(
        legacyId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      expect(result, EventCancellationStatus.cancelled);
      expect(await Alarm.getAlarm(legacyId), isNull);
    });

    test('10. Repeated cancellation is idempotent and safe', () async {
      const alarmId = 26110820;
      final futureTime = DateTime.now().add(const Duration(hours: 4));

      await repository.scheduleAdhanAlarm(
        id: alarmId,
        title: 'صلاة العصر',
        body: 'حي على الصلاة',
        scheduledTime: futureTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // First cancellation
      final first = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );
      expect(first, EventCancellationStatus.cancelled);

      // Second cancellation: alarm is now absent
      final second = await repository.cancelAlarmSafely(
        alarmId,
        expectedScheduledTime: futureTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );
      expect(second, EventCancellationStatus.alreadyAbsent, reason: 'Repeated cancellation is safe and idempotent');
    });

    test('11. Targeted cancellation isolates target and strictly preserves other scheduled alarms', () async {
      const targetId = 26110810; // Dhuhr
      const siblingId = 26110820; // Asr
      final dhuhrTime = DateTime.now().add(const Duration(hours: 3));
      final asrTime = DateTime.now().add(const Duration(hours: 6));

      await repository.scheduleAdhanAlarm(
        id: targetId,
        title: 'صلاة الظهر',
        body: 'حي على الصلاة',
        scheduledTime: dhuhrTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );
      await repository.scheduleAdhanAlarm(
        id: siblingId,
        title: 'صلاة العصر',
        body: 'حي على الصلاة',
        scheduledTime: asrTime,
        assetAudioPath: 'assets/sounds/adhan.mp3',
      );

      // Cancel only Dhuhr
      final result = await repository.cancelAlarmSafely(
        targetId,
        expectedScheduledTime: dhuhrTime,
        expectedAssetAudioPath: 'assets/sounds/adhan.mp3',
      );

      expect(result, EventCancellationStatus.cancelled);
      expect(await Alarm.getAlarm(targetId), isNull, reason: 'Target Dhuhr alarm must be canceled');
      expect(await Alarm.getAlarm(siblingId), isNotNull, reason: 'Sibling Asr alarm must be strictly preserved');
    });
  });
}
