import 'package:adhan/adhan.dart'; // مكتبة الحسابات الفلكية
import '../models/prayer_time_model.dart'; // تأكد إن اسم الملف هنا مطابق للي عندك

class PrayerTimesLocalDataSource {
  
  // دالة لجلب المواقيت بناءً على الإحداثيات والتاريخ
  Future<PrayerTimesModel> getPrayerTimes({
    required Coordinates coordinates,
    required DateTime date,
  }) async {
    
    // 1. تحديد طريقة الحساب (مثلاً: هيئة المساحة المصرية)
    // ممكن نغيرها بعدين نخلي المستخدم يختارها من الإعدادات
    final params = CalculationMethod.egyptian.getParameters();
    params.madhab = Madhab.shafi; // المذهب الشافعي (الافتراضي)

    // 2. حساب المواقيت باستخدام المكتبة
    final prayerTimes = PrayerTimes(coordinates, DateComponents.from(date), params);

    // 3. تحويل النتيجة للموديل بتاعنا وإرجاعها
    return PrayerTimesModel.fromAdhanObject(prayerTimes);
  }
}