import 'package:adhan/adhan.dart'; // مكتبة الحسابات الفلكية
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';
import '../models/prayer_time_model.dart'; // تأكد إن اسم الملف هنا مطابق للي عندك

class PrayerTimesLocalDataSource {
  
  // دالة لجلب المواقيت بناءً على الإحداثيات والتاريخ
  Future<PrayerTimesModel> getPrayerTimes({
    required Coordinates coordinates,
    required DateTime date,
    String? method,
    String? madhab,
  }) async {
    
    // 1. تحديد طريقة الحساب
    final params = method != null 
        ? CalculationMethodHelper.getParametersFromMethodId(method)
        : CalculationMethod.egyptian.getParameters();
        
    params.madhab = (madhab == 'hanafi') ? Madhab.hanafi : Madhab.shafi;

    // 2. حساب المواقيت باستخدام المكتبة
    final prayerTimes = PrayerTimes(coordinates, DateComponents.from(date), params);

    // 3. تحويل النتيجة للموديل بتاعنا وإرجاعها
    return PrayerTimesModel.fromAdhanObject(prayerTimes);
  }
}