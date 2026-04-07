import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';

class CheckIfSchedulingNeededUseCase {
  final SharedPreferences pref;

  CheckIfSchedulingNeededUseCase({required this.pref});

  bool execute() {
    final String? scheduledUntilStr = pref.getString('scheduled_until_date');

    if (scheduledUntilStr != null) {
      final DateTime scheduledUntil = DateTime.parse(scheduledUntilStr);

      // لو لسة فاضل أكتر من يومين على آخر إشعار مجدول، نوقف ومحسبش حاجة!
      if (scheduledUntil.difference(DateTime.now()).inDays > 2) {
        log(
          "✅ الإشعارات مجدولة مسبقاً حتى يوم $scheduledUntil. تخطي عملية الجدولة لتوفير المعالج.",
        );
        return false; // يعني مش محتاجين نجدول
      }
    }
      log(
        "⚠️ الإشعارات غير مجدولة أو قربت تنتهي. نحتاج نجدد الجدولة! (Last scheduled until: ${scheduledUntilStr ?? "None"})",
      );
    return true; // يعني محتاجين نجدول
  }
}
