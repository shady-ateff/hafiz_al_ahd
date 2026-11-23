import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/data/focus_poc_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusPoCPermissionStatus Tests', () {
    test('isAllGranted returns true only when usage access and overlay are granted', () {
      const allGranted = FocusPoCPermissionStatus(
        hasUsageAccess: true,
        hasOverlayPermission: true,
        canScheduleExactAlarms: true,
      );
      expect(allGranted.isAllGranted, isTrue);

      const missingUsage = FocusPoCPermissionStatus(
        hasUsageAccess: false,
        hasOverlayPermission: true,
        canScheduleExactAlarms: true,
      );
      expect(missingUsage.isAllGranted, isFalse);

      const missingOverlay = FocusPoCPermissionStatus(
        hasUsageAccess: true,
        hasOverlayPermission: false,
        canScheduleExactAlarms: true,
      );
      expect(missingOverlay.isAllGranted, isFalse);
    });

    test('fromMap parses map correctly with fallbacks', () {
      final status = FocusPoCPermissionStatus.fromMap({
        'hasUsageAccess': true,
        'hasOverlayPermission': true,
        'canScheduleExactAlarms': false,
      });

      expect(status.hasUsageAccess, isTrue);
      expect(status.hasOverlayPermission, isTrue);
      expect(status.canScheduleExactAlarms, isFalse);
      expect(status.isAllGranted, isTrue);
    });
  });

  group('FocusPoCChannel MethodChannel Tests', () {
    const channel = MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');
    final List<MethodCall> log = [];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'checkPermissions':
            return {
              'hasUsageAccess': true,
              'hasOverlayPermission': true,
              'canScheduleExactAlarms': true,
            };
          case 'isServiceRunning':
            return true;
          case 'startMonitoring':
            return true;
          case 'stopMonitoring':
            return true;
          case 'getCurrentForegroundApp':
            return {
              'packageName': 'com.google.android.youtube',
              'isExempted': false,
            };
          default:
            return null;
        }
      });
      log.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('checkPermissions calls native method and parses properly', () async {
      final res = await FocusPoCChannel.checkPermissions();
      expect(res.hasUsageAccess, isTrue);
      expect(res.hasOverlayPermission, isTrue);
      expect(res.canScheduleExactAlarms, isTrue);
      expect(log.first.method, 'checkPermissions');
    });

    test('startMonitoring passes wardTitle correctly', () async {
      final res = await FocusPoCChannel.startMonitoring(wardTitle: 'أذكار المساء');
      expect(res, isTrue);
      expect(log.first.method, 'startMonitoring');
      expect(log.first.arguments, {'wardTitle': 'أذكار المساء', 'sessionId': null});
    });

    test('stopMonitoring calls stopMonitoring native method', () async {
      final res = await FocusPoCChannel.stopMonitoring();
      expect(res, isTrue);
      expect(log.first.method, 'stopMonitoring');
    });

    test('getCurrentForegroundApp returns package and exemption info', () async {
      final res = await FocusPoCChannel.getCurrentForegroundApp();
      expect(res['packageName'], 'com.google.android.youtube');
      expect(res['isExempted'], isFalse);
    });
  });
}
