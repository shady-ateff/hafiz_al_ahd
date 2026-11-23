import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/data/focus_poc_channel.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/presentation/widgets/poc_status_card.dart';

void main() {
  testWidgets('PoCStatusCard displays running state and permission rows correctly', (tester) async {
    const perms = FocusPoCPermissionStatus(
      hasUsageAccess: true,
      hasOverlayPermission: false,
      canScheduleExactAlarms: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PoCStatusCard(
            permissions: perms,
            isServiceRunning: true,
            currentApp: 'com.shadyatef.hafiz_alahd',
            isAppExempted: true,
            onRefreshPermissions: () {},
            onOpenUsageSettings: () {},
            onOpenOverlaySettings: () {},
            onOpenExactAlarmSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('الخدمة نشطة (Monitoring)'), findsOneWidget);
    expect(find.text('com.shadyatef.hafiz_alahd'), findsOneWidget);
    expect(find.text('مستثنى (آمن)'), findsOneWidget);
    expect(find.text('تفعيل'), findsOneWidget); // For missing overlay permission
  });
}
