
import 'dart:developer';

import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';

class FetchPrayerTimesOrchestrator {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final SaveLocationUseCase saveLocationUseCase;

  FetchPrayerTimesOrchestrator({
    required this.getPrayerTimesUseCase,
    required this.saveLocationUseCase,
  });

  Future<Either<Failure, PrayerTimesEntity>> execute({
    required double lat,
    required double lng,
    required String city,
    String? country,
    DateTime? date,
  }) async {
    // 1. تحديد طريقة الحساب بناءً على الدولة
    String method = '3'; // Default
    if (country != null) {
      method = CalculationMethodHelper.getMethodForCountry(country);
    }
    log("[Orchestrator] Determined calculation method: $method for country: $country");

    // 2. حفظ الموقع في الكاش
    await saveLocationUseCase(
      LocationEntity(
        latitude: lat,
        longitude: lng,
        city: city,
        country: country,
      ),
    );
    log("[Orchestrator] Location saved: $city, $country (lat: $lat, lng: $lng)");
    // 3. جلب المواقيت من الـ API أو الـ Local
    log("[Orchestrator] Fetching prayer times with method: $method for date: ${date ?? DateTime.now()}");
    return await getPrayerTimesUseCase(
      latitude: lat,
      longitude: lng,
      date: date ?? DateTime.now(),
      city: city,
      country: country,
      method: method,
    );
  }
}