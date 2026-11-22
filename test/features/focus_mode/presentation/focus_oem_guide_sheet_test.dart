import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/widgets/focus_oem_guide_sheet.dart';

void main() {
  testWidgets('FocusOEMGuideSheet renders manufacturer tabs and guidelines', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => FocusOEMGuideSheet.show(context),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('إرشادات تثبيت الخدمة وحماية البطارية'), findsOneWidget);

    // Verify OEM Tabs
    expect(find.widgetWithText(Tab, 'شاومي / بوكو'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'سامسونج'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'هواوي / هونر'), findsOneWidget);

    // Verify initial Xiaomi guidance steps
    expect(find.textContaining('Autostart'), findsOneWidget);
    expect(find.textContaining('No restrictions'), findsOneWidget);

    // Switch to Samsung tab
    await tester.tap(find.widgetWithText(Tab, 'سامسونج'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Never sleeping apps'), findsOneWidget);
    expect(find.textContaining('Unrestricted'), findsOneWidget);

    // Close button
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('إرشادات تثبيت الخدمة وحماية البطارية'), findsNothing);
  });
}
