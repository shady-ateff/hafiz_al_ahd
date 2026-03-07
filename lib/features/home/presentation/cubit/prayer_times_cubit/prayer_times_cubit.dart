import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hafiz_al_ahd/core/services/location_service.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';

class PrayerTimesCubit extends Cubit<PrayerTimesStates> {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final SaveLocationUseCase saveLocationUseCase;
  final GetCachedLocationUseCase getCachedLocationUseCase;

  PrayerTimesCubit({
    required this.getPrayerTimesUseCase,
    required PrayerTimesInitial initialState,
    required this.saveLocationUseCase,
    required this.getCachedLocationUseCase,
  }) : super(initialState);

  Future<void> fetchPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    emit(PrayerTimesLoading());
    log(
      'Fetching prayer times for lat: $latitude, long: $longitude, date: $date',
    );
    try {
      final result = await getPrayerTimesUseCase(
        latitude: latitude,
        longitude: longitude,
        date: date,
        city: city,
        country: country,
        method: method,
      );

      result.fold(
        (failure) => emit(PrayerTimesError(failure.message)),
        (prayerTimes) => emit(PrayerTimesLoaded(prayerTimes, city: city)),
      );
    } catch (e) {
      emit(PrayerTimesError(e.toString()));
    }
  }

  Future<void> fetchPrayerTimesByLocation() async {
    late Position position;
    try {
      emit(PrayerTimesLoading());
      position = await LocationService.determinePosition();
      String cityName = await LocationService.getCityName(position);

      // حفظ الموقع الجديد في الكاش للمرات القادمة
      await saveLocationUseCase(
        LocationEntity(
          latitude: position.latitude,
          longitude: position.longitude,
          city: cityName,
        ),
      );

      await fetchPrayerTimes(
        latitude: position.latitude,
        longitude: position.longitude,
        date: DateTime.now(),
        city: cityName,
      );
    } catch (e) {
      print("GPS Failed, loading from Cache... Error was: ${e.toString()}");
      // بدلاً من إرسال خطأ فوراً، نحاول تحميل الكاش أولاً
      await loadPrayerTimesFromCache();
    }
  }

  Future<void> fetchPrayerTimesManually(
    double lat,
    double lng,
    String city,
  ) async {
    emit(PrayerTimesLoading());

    // نحفظ الموقع اللي اليوزر اختاره يدوياً في الكاش عشان المرات الجاية
    await saveLocationUseCase(
      LocationEntity(latitude: lat, longitude: lng, city: city),
    );

    // نحسب الصلوات
    await _calculateAndEmitPrayerTimes(lat, lng, city);
  }

  // -------------------------------------------------------------------
  // دالة مساعدة (Helper) عشان منكررش كود حساب الصلوات في كل مرة
  Future<void> _calculateAndEmitPrayerTimes(
    double lat,
    double lng,
    String city,
  ) async {
    final result = await getPrayerTimesUseCase(
      latitude: lat,
      longitude: lng,
      date: DateTime.now(),
      city: city,
    );

    result.fold(
      (failure) => emit(PrayerTimesError(failure.message)),
      (prayerTimes) => emit(PrayerTimesLoaded(prayerTimes)),
    );
  }

  // -------------------------------------------------------------------
  Future<void> loadPrayerTimesFromCache() async {
    emit(PrayerTimesLoading());

    final result = await getCachedLocationUseCase();

    result.fold((failure) => emit(PrayerTimesNeedsManualLocation()), (
      location,
    ) async {
      await _calculateAndEmitPrayerTimes(
        location.latitude,
        location.longitude,
        location.city,
      );
    });
  }
}
