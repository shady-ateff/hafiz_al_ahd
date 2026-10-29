import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GetPrayerTimesUseCase {
  final PrayerTimesRepo prayerTimesRepo;
  final SharedPreferences pref;
  GetPrayerTimesUseCase(this.prayerTimesRepo, {required this.pref});

  Future<Either<Failure, PrayerTimesEntity>> call({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    // 1. استخراج الدولة بناءً على الكود أو الإحداثيات الجغرافية الفعلية
    String? effectiveCountry = CalculationMethodHelper.resolveCountryCode(
      country,
      latitude,
      longitude,
    );

    // 2. إذا لم تُعرف الدولة، نفحص الكاش فقط إذا كانت الإحداثيات متوافقة معه
    if (effectiveCountry == null || effectiveCountry.trim().isEmpty) {
      final cachedJson = pref.getString('CACHED_LOCATION');
      if (cachedJson != null) {
        try {
          final decoded = json.decode(cachedJson);
          final double? cachedLat = (decoded['lat'] as num?)?.toDouble();
          final double? cachedLng = (decoded['lng'] as num?)?.toDouble();
          if (cachedLat != null && cachedLng != null) {
            final latDiff = (cachedLat - latitude).abs();
            final lngDiff = (cachedLng - longitude).abs();
            // التحقق من أن الكاش لنفس المنطقة الجغرافية (أقل من 3 درجات)
            if (latDiff < 3.0 && lngDiff < 3.0) {
              effectiveCountry = decoded['country'] as String?;
            }
          }
        } catch (_) {}
      }
    }

    final String? prefMethod = pref.getString('calculation_method');
    final String? prefMadhab = pref.getString('madhab');
    final double? customFajrAngle = pref.getDouble('custom_fajr_angle');
    final double? customIshaAngle = pref.getDouble('custom_isha_angle');

    String defaultMethod = method ?? '3';
    if (method == null && effectiveCountry != null) {
      defaultMethod = CalculationMethodHelper.getMethodForCountry(effectiveCountry);
    }

    final String finalMethod =
        (prefMethod != null && prefMethod != 'auto')
            ? prefMethod
            : defaultMethod;

    final result = await prayerTimesRepo.getPrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: date,
      city: city,
      country: effectiveCountry,
      method: finalMethod,
      madhab: prefMadhab,
      customFajrAngle: customFajrAngle,
      customIshaAngle: customIshaAngle,
    );

    // تطبيق فرق التوقيت الصيفي لو المستخدم فعّله يدوياً من الإعدادات
    final int dstOffset = pref.getInt('dst_offset_minutes') ?? 0;

    // تطبيق إزاحات دقائق الصلوات المخصصة (+/- دقائق)
    final int fajrOffset = pref.getInt('prayer_offset_fajr') ?? 0;
    final int sunriseOffset = pref.getInt('prayer_offset_sunrise') ?? 0;
    final int dhuhrOffset = pref.getInt('prayer_offset_dhuhr') ?? 0;
    final int asrOffset = pref.getInt('prayer_offset_asr') ?? 0;
    final int maghribOffset = pref.getInt('prayer_offset_maghrib') ?? 0;
    final int ishaOffset = pref.getInt('prayer_offset_isha') ?? 0;

    return result.map(
      (entity) => entity
          .applyDstOffset(dstOffset)
          .applyOffsets(
            fajr: fajrOffset,
            sunrise: sunriseOffset,
            dhuhr: dhuhrOffset,
            asr: asrOffset,
            maghrib: maghribOffset,
            isha: ishaOffset,
          ),
    );
  }
}
