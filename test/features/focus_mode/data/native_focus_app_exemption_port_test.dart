import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/native_focus_app_exemption_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeFocusAppExemptionPort port;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'getInstalledApps':
            return [
              {
                'packageName': 'com.google.android.calculator',
                'appName': 'الآلة الحاسبة',
                'isSystemApp': false,
                'isSystemCritical': false,
                'isExempt': false,
                'iconBase64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              },
            ];
          case 'setExemptions':
            return true;
          case 'getSystemCriticalPackages':
            return ['com.android.dialer', 'com.android.launcher'];
          default:
            return null;
        }
      },
    );

    port = NativeFocusAppExemptionPort();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.shadyatef.hafiz_alahd/focus_poc'),
      null,
    );
  });

  group('NativeFocusAppExemptionPort MethodChannel Tests', () {
    test('getInstalledApps parses installed applications and metadata', () async {
      final apps = await port.getInstalledApps();

      expect(apps.length, 1);
      expect(apps.first.packageName, 'com.google.android.calculator');
      expect(apps.first.appName, 'الآلة الحاسبة');
      expect(apps.first.iconBase64, isNotNull);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'getInstalledApps');
    });

    test('syncExemptionsToNative passes exemptPackages list', () async {
      final result = await port.syncExemptionsToNative(['com.calc', 'com.notes']);

      expect(result, isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'setExemptions');
      expect(methodCalls.first.arguments, {
        'exemptPackages': ['com.calc', 'com.notes'],
      });
    });

    test('getSystemCriticalPackages parses list of string package names', () async {
      final criticals = await port.getSystemCriticalPackages();

      expect(criticals.length, 2);
      expect(criticals.contains('com.android.dialer'), isTrue);
      expect(criticals.contains('com.android.launcher'), isTrue);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'getSystemCriticalPackages');
    });
  });
}
