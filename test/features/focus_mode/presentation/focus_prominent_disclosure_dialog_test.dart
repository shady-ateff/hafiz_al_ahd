import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/widgets/focus_prominent_disclosure_dialog.dart';

void main() {
  testWidgets('FocusProminentDisclosureDialog renders disclosure details and triggers callbacks', (tester) async {
    bool confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                FocusProminentDisclosureDialog.show(
                  context,
                  onConfirm: () => confirmed = true,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify Title and prominent disclosure statements
    expect(find.text('إفصاح إذن الوصول لبيانات الاستخدام'), findsOneWidget);
    expect(find.textContaining('معالجة محلية آمنة 100%'), findsOneWidget);
    expect(find.textContaining('حجب المشتتات أثناء الورد'), findsOneWidget);
    expect(find.textContaining('حماية التطبيقات المهمة'), findsOneWidget);

    // Tap confirm button
    await tester.tap(find.text('متابعة وتفعيل الإذن'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
    expect(find.text('إفصاح إذن الوصول لبيانات الاستخدام'), findsNothing);
  });

  testWidgets('FocusProminentDisclosureDialog cancels when "ليس الآن" is tapped', (tester) async {
    bool confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                FocusProminentDisclosureDialog.show(
                  context,
                  onConfirm: () => confirmed = true,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ليس الآن'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.text('إفصاح إذن الوصول لبيانات الاستخدام'), findsNothing);
  });
}
