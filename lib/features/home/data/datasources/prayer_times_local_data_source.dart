import 'package:adhan/adhan.dart'; // مكتبة الحسابات الفلكية
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/prayer_time_model.dart';

class PrayerTimesLocalDataSource {
  
  // دالة لجلب المواقيت بناءً على الإحداثيات والتاريخ
  Future<PrayerTimesModel> getPrayerTimes({
    required Coordinates coordinates,
    required DateTime date,
    String? method,
    String? madhab,
    String? countryCode,
    double? customFajrAngle,
    double? customIshaAngle,
  }) async {
    // التأكد من تهيئة المناطق الزمنية
    _ensureTimezonesInitialized();

    // استنتاج كود الدولة الفعلي مع التحقق المزدوج من الإحداثيات لمنع تضارب الكاش
    final String? effectiveCountry = CalculationMethodHelper.resolveCountryCode(
      countryCode,
      coordinates.latitude,
      coordinates.longitude,
    );

    // 1. تحديد طريقة الحساب
    // لو الدولة المغرب والمستخدم لم يختر طريقة محددة يدوياً، نستخدم إعدادات وزارة الأوقاف المغربية (طريقة 14)
    String resolvedMethod = method ?? '3';
    if (CalculationMethodHelper.isMorocco(effectiveCountry) &&
        (method == null || method == 'auto' || method == '14')) {
      resolvedMethod = '14';
    }

    final params = CalculationMethodHelper.getParametersFromMethodId(
      resolvedMethod,
      customFajrAngle: customFajrAngle,
      customIshaAngle: customIshaAngle,
    );
    params.madhab = (madhab == 'hanafi') ? Madhab.hanafi : Madhab.shafi;

    // 2. حساب المواقيت الفلكية باستخدام باكدج adhan
    // مخرجات adhan تمثل أوقات فلكية محددة بـ UTC
    final prayerTimes = PrayerTimes(
      coordinates,
      DateComponents.from(date),
      params,
    );

    // 3. تحديد المنطقة الزمنية الصحيحة (IANA Timezone)
    // ⚠️ خصوصية التوقيت الصيفي للمغرب تطبق فقط إذا كان الموقع الجغرافي الفعلي بالمغرب
    final bool isMoroccoLocation = CalculationMethodHelper.isMorocco(effectiveCountry);

    String? timezoneId = CalculationMethodHelper.getTimezoneForCountry(effectiveCountry);
    if (timezoneId == null && isMoroccoLocation) {
      timezoneId = 'Africa/Casablanca';
    }

    final tz.Location targetLocation = timezoneId != null
        ? tz.getLocation(timezoneId)
        : tz.local;

    // 4. التحويل النهائي (Mapping to UI / Cubit):
    // ----------------------------------------------------------------------
    // للمغرب فقطططططط (إذا كان الموقع الجغرافي بالمغرب):
    // وزارة الأوقاف المغربية تعتمد توقيت غرينتش (GMT 0) لحساب ونشر مواقيت الصلاة،
    // بينما التوقيت الافتراضي لساعة الهاتف في المغرب هو (GMT+1) خارج رمضان.
    // نقوم بطرح فرق الساعة (1 ساعة) لضبط وقت الصلاة مع غرينتش
    // مع الحفاظ على التايم زون الأصلي للجهاز (targetLocation) لثبات العداد والإشعارات.
    // وفي رمضان يعود المغرب لـ (GMT 0) تلقائياً فلا يتم خصم شيء.
    // ----------------------------------------------------------------------
    if (isMoroccoLocation) {
      return PrayerTimesModel(
        fajr: _adjustForMorocco(prayerTimes.fajr, targetLocation),
        sunrise: _adjustForMorocco(prayerTimes.sunrise, targetLocation),
        dhuhr: _adjustForMorocco(prayerTimes.dhuhr, targetLocation),
        asr: _adjustForMorocco(prayerTimes.asr, targetLocation),
        maghrib: _adjustForMorocco(prayerTimes.maghrib, targetLocation),
        isha: _adjustForMorocco(prayerTimes.isha, targetLocation),
      );
    }

    // باقي الدول (مصر، الخليج، إلخ): التحويل المباشر بالمنطقة الزمنية الصحيحة للدولة
    return PrayerTimesModel(
      fajr: tz.TZDateTime.from(prayerTimes.fajr.toUtc(), targetLocation),
      sunrise: tz.TZDateTime.from(prayerTimes.sunrise.toUtc(), targetLocation),
      dhuhr: tz.TZDateTime.from(prayerTimes.dhuhr.toUtc(), targetLocation),
      asr: tz.TZDateTime.from(prayerTimes.asr.toUtc(), targetLocation),
      maghrib: tz.TZDateTime.from(prayerTimes.maghrib.toUtc(), targetLocation),
      isha: tz.TZDateTime.from(prayerTimes.isha.toUtc(), targetLocation),
    );
  }

  /// دالة مخصصة للمغرب فقط:
  /// تخصم ساعة واحدة إذا كان التوقيت الصيفي/الإضافي مفعلاً (UTC+1) ليطابق توقيت غرينتش (0 GMT)،
  /// مع تثبيت الـ TZDateTime في منطقة المغرب للحفاظ على توافق العداد والإشعارات مع ساعة الهاتف.
  DateTime _adjustForMorocco(DateTime prayerTimeUtc, tz.Location targetLocation) {
    final tzDateTime = tz.TZDateTime.from(prayerTimeUtc.toUtc(), targetLocation);
    final int offsetHours = tzDateTime.timeZoneOffset.inHours;
    if (offsetHours > 0) {
      return tzDateTime.subtract(Duration(hours: offsetHours));
    }
    return tzDateTime;
  }

  void _ensureTimezonesInitialized() {
    try {
      tz.getLocation('Africa/Casablanca');
    } catch (_) {
      tz.initializeTimeZones();
    }
  }
}
