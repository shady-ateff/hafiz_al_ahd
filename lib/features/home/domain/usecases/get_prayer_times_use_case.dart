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
    );

    // تطبيق فرق التوقيت الصيفي لو المستخدم فعّله يدوياً من الإعدادات
    final int dstOffset = pref.getInt('dst_offset_minutes') ?? 0;
    return result.map((entity) => entity.applyDstOffset(dstOffset));
  }
}
