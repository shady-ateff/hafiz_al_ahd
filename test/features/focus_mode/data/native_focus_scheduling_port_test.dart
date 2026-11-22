import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/native_focus_scheduling_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeFocusSchedulingPort port;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'scheduleAlarm':
            return true;
          case 'cancelAlarm':
            return true;
          case 'checkPermissions':
            return {
              'hasUsageAccess': true,
              'hasOverlayPermission': true,
              'canScheduleExactAlarms': true,
            };
          case 'openExactAlarmSettings':
            return true;
          default:
            return null;
        }
      },
    );

    port = NativeFocusSchedulingPort();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      null,
    );
  });

  group('NativeFocusSchedulingPort MethodChannel Tests', () {
    test('scheduleAlarm passes correct arguments to native channel', () async {
      final triggerAt = DateTime(2026, 11, 22, 7, 30);
      final result = await port.scheduleAlarm(
        scheduleId: 'sched_test_1',
        triggerAt: triggerAt,
        wardTitle: 'أذكار الصباح',
        wardType: FocusWardType.morningAzkar,
      );

      expect(result, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'scheduleAlarm');
      expect(methodCalls.first.arguments, {
        'scheduleId': 'sched_test_1',
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        'wardTitle': 'أذكار الصباح',
        'wardType': 'morningAzkar',
      });
    });

    test('cancelAlarm passes scheduleId to native channel', () async {
      final result = await port.cancelAlarm('sched_test_1');

      expect(result, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'cancelAlarm');
      expect(methodCalls.first.arguments, {
        'scheduleId': 'sched_test_1',
      });
    });

    test('canScheduleExactAlarms parses permission boolean from checkPermissions', () async {
      final canExact = await port.canScheduleExactAlarms();

      expect(canExact, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'checkPermissions');
    });

    test('requestExactAlarmPermission invokes openExactAlarmSettings', () async {
      await port.requestExactAlarmPermission();

      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'openExactAlarmSettings');
    });
  });
}
