import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/app_permissions_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pocChannel =
      MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');
  const MethodChannel permHandlerChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pocChannel, (call) async {
      if (call.method == 'checkPermissions') {
        return {
          'hasUsageAccess': false,
          'hasOverlayPermission': false,
          'canScheduleExactAlarms': true,
        };
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permHandlerChannel, (call) async {
      if (call.method == 'checkPermissionStatus') {
        // Return 0 for denied, 1 for granted
        final int permission = call.arguments as int;
        // notification = 17, location = 3, ignoreBattery = 19
        if (permission == 17) {
          return 1; // granted
        }
        return 0; // denied
      }
      return 0;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pocChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permHandlerChannel, null);
  });

  Widget buildTestWidget() {
    return BlocProvider(
      create: (_) => ThemeCubit(),
      child: const MaterialApp(
        home: AppPermissionsScreen(),
      ),
    );
  }

  testWidgets('AppPermissionsScreen renders title, summary, and permission cards',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify App Bar
    expect(find.text('فحص صلاحيات التطبيق'), findsOneWidget);

    // Verify Summary banner
    expect(find.textContaining('صلاحيات'), findsWidgets);
    expect(find.text('تحديث الحالة'), findsOneWidget);

    // Verify Section Headers
    expect(
      find.text('صلاحيات الأذان ومواقيت الصلاة الأساسية'),
      findsOneWidget,
    );
    expect(
      find.text('صلاحيات وضع التركيز وحماية الأوراد'),
      findsOneWidget,
    );

    // Verify Permission Titles
    expect(find.text('إشعارات الأذان والتنبيهات'), findsOneWidget);
    expect(find.text('المنبهات الدقيقة (Exact Alarms)'), findsOneWidget);
    expect(find.text('تجاهل تحسين البطارية'), findsOneWidget);
    expect(find.text('تحديد الموقع الجغرافي'), findsOneWidget);
    expect(find.text('الظهور فوق التطبيقات (Overlay)'), findsOneWidget);
    expect(find.text('الوصول لبيانات الاستخدام (Usage Access)'), findsOneWidget);

    // Verify Impact warning section exists for ungranted permissions
    expect(
      find.text('ما الذي سيتأثر عند إغلاق هذه الصلاحية؟'),
      findsWidgets,
    );

    // Verify Action button for ungranted items
    expect(find.text('تفعيل الصلاحية الآن'), findsWidgets);

    // Verify OEM guide card
    expect(
      find.text('إرشادات مصنّعي الهواتف (شاومي / سامسونج / هواوي)'),
      findsOneWidget,
    );
  });

  testWidgets('AppPermissionsScreen does not overflow on small narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 2.0, 600 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('فحص صلاحيات التطبيق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
