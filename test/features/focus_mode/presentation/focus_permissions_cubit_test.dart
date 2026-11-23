import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_permissions/focus_permissions_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusPermissionsCubit cubit;
  final List<MethodCall> calls = [];
  Map<String, dynamic> mockPermissions = {
    'hasUsageAccess': true,
    'hasOverlayPermission': true,
    'canScheduleExactAlarms': true,
  };

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      (MethodCall call) async {
        calls.add(call);
        switch (call.method) {
          case 'checkPermissions':
            return mockPermissions;
          case 'openUsageAccessSettings':
          case 'openOverlaySettings':
          case 'openExactAlarmSettings':
            return true;
          default:
            return null;
        }
      },
    );

    cubit = FocusPermissionsCubit();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      null,
    );
    cubit.close();
  });

  group('FocusPermissionsCubit Tests', () {
    test('checkPermissions sets isAllGranted to true when all are granted', () async {
      mockPermissions = {
        'hasUsageAccess': true,
        'hasOverlayPermission': true,
        'canScheduleExactAlarms': true,
      };

      await cubit.checkPermissions();

      expect(cubit.state.hasUsageAccess, isTrue);
      expect(cubit.state.hasOverlayPermission, isTrue);
      expect(cubit.state.canScheduleExactAlarms, isTrue);
      expect(cubit.state.isAllGranted, isTrue);
      expect(cubit.state.isLoading, isFalse);
    });

    test('checkPermissions sets isAllGranted to false when any permission is missing', () async {
      mockPermissions = {
        'hasUsageAccess': true,
        'hasOverlayPermission': false,
        'canScheduleExactAlarms': true,
      };

      await cubit.checkPermissions();

      expect(cubit.state.hasUsageAccess, isTrue);
      expect(cubit.state.hasOverlayPermission, isFalse);
      expect(cubit.state.isAllGranted, isFalse);
    });

    test('open settings methods invoke corresponding channel methods', () async {
      await cubit.openUsageAccessSettings();
      await cubit.openOverlaySettings();
      await cubit.openExactAlarmSettings();

      final invokedMethods = calls.map((c) => c.method).toList();
      expect(invokedMethods, contains('openUsageAccessSettings'));
      expect(invokedMethods, contains('openOverlaySettings'));
      expect(invokedMethods, contains('openExactAlarmSettings'));
    });
  });
}
