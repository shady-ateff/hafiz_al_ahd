import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hafiz_al_ahd/core/services/location_service.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
// 👈 استيراد الـ UseCase الجديد
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/show_sticky_notification_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';

class PrayerTimesCubit extends Cubit<PrayerTimesStates> {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final SaveLocationUseCase saveLocationUseCase;
  final GetCachedLocationUseCase getCachedLocationUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  // 👈 تعريف الـ UseCase بتاع الإشعار الثابت
  final ShowStickyNotificationUseCase showStickyNotificationUseCase;
  final GetIqamaDelaysUseCase getIqamaDelaysUseCase = GetIqamaDelaysUseCase();

  PrayerTimesCubit({
    required this.getPrayerTimesUseCase,
    required PrayerTimesInitial initialState,
    required this.saveLocationUseCase,
    required this.getCachedLocationUseCase,
    required this.schedulePrayerUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.showStickyNotificationUseCase,
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

      result.fold((failure) => emit(PrayerTimesError(failure.message)), (
        prayerTimes,
      ) {
        emit(PrayerTimesLoaded(prayerTimes, city: city));

        _scheduleNotificationsForNext6Days(latitude, longitude, city ?? '');

        // 👈 السطر السحري لتشغيل الإشعار الثابت بتاع الصلاة القادمة
        _updateStickyCountdown(prayerTimes);
      });
    } catch (e) {
      emit(PrayerTimesError(e.toString()));
    }
  }

  // -------------------------------------------------------------------
  // 👈 دالة جديدة: بتحسب الصلاة الجاية إمتى وتشغل الإشعار الثابت بالعداد
  Future<void> _updateStickyCountdown(var prayerTimes) async {
    DateTime now = DateTime.now();
    DateTime? nextTime;
    String? nextName;

    if (prayerTimes.fajr!.isAfter(now)) {
      nextTime = prayerTimes.fajr;
      nextName = 'الفجر';
    } else if (prayerTimes.dhuhr!.isAfter(now)) {
      nextTime = prayerTimes.dhuhr;
      nextName = 'الظهر';
    } else if (prayerTimes.asr!.isAfter(now)) {
      nextTime = prayerTimes.asr;
      nextName = 'العصر';
    } else if (prayerTimes.maghrib!.isAfter(now)) {
      nextTime = prayerTimes.maghrib;
      nextName = 'المغرب';
    } else if (prayerTimes.isha!.isAfter(now)) {
      nextTime = prayerTimes.isha;
      nextName = 'العشاء';
    } else {
      // لو العشاء أذنت، يبقى الصلاة الجاية هي الفجر بتاع بكرة
      nextTime = prayerTimes.fajr!.add(const Duration(days: 1));
      nextName = 'الفجر';
    }

    if (nextTime != null) {
      log("⏳ Starting Sticky Countdown for: $nextName at $nextTime");
      await showStickyNotificationUseCase.execute(
        id: 999, // رقم ثابت للإشعار ده عشان دايماً يمسح نفسه ويتحدث
        title: 'الصلاة القادمة: $nextName',
        body: 'متبقي على رفع الأذان',
        nextPrayerTime: nextTime,
      );
    }
  }
  // -------------------------------------------------------------------

  Future<void> fetchPrayerTimesByLocation() async {
    late Position position;
    try {
      emit(PrayerTimesLoading());
      position = await LocationService.determinePosition();
      LocationEntity locationDetails = await LocationService.getLocationDetails(
        position,
      );
      String cityName = locationDetails.city;

      String method = '3';
      if (locationDetails.country != null) {
        method = CalculationMethodHelper.getMethodForCountry(
          locationDetails.country!,
        );
      }

      await saveLocationUseCase(
        LocationEntity(
          latitude: position.latitude,
          longitude: position.longitude,
          city: cityName,
          country: locationDetails.country,
        ),
      );

      await fetchPrayerTimes(
        latitude: position.latitude,
        longitude: position.longitude,
        date: DateTime.now(),
        city: cityName,
        country: locationDetails.country,
        method: method,
      );
    } catch (e) {
      print("GPS Failed, loading from Cache... Error was: ${e.toString()}");
      await loadPrayerTimesFromCache();
    }
  }

  Future<void> fetchPrayerTimesManually(
    double lat,
    double lng,
    String city, [
    String? country,
  ]) async {
    emit(PrayerTimesLoading());

    String method = '3';
    if (country != null) {
      method = CalculationMethodHelper.getMethodForCountry(country);
    }

    await saveLocationUseCase(
      LocationEntity(
        latitude: lat,
        longitude: lng,
        city: city,
        country: country,
      ),
    );

    await fetchPrayerTimes(
      latitude: lat,
      longitude: lng,
      date: DateTime.now(),
      city: city,
      country: country,
      method: method,
    );
  }

  Future<void> loadPrayerTimesFromCache() async {
    emit(PrayerTimesLoading());

    final result = await getCachedLocationUseCase();

    result.fold((failure) => emit(PrayerTimesNeedsManualLocation()), (
      location,
    ) async {
      String method = '3';
      if (location.country != null) {
        method = CalculationMethodHelper.getMethodForCountry(location.country!);
      }

      await fetchPrayerTimes(
        latitude: location.latitude,
        longitude: location.longitude,
        date: DateTime.now(),
        city: location.city,
        country: location.country,
        method: method,
      );
    });
  }
Future<void> _scheduleNotificationsForNext6Days(
    double lat,
    double lng,
    String city,
  ) async {
    await cancelAllNotificationsUseCase.execute();
    log("Notifications cleared. Scheduling new notifications for the next 6 days......");
    
    int notificationId = 0; 

    for (int i = 0; i < 6; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final result = await getPrayerTimesUseCase(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
      );

      log("Fetched prayer times for ${date.toLocal()} - scheduling notifications...");
      
      // 👈 2. لازم نعمل await هنا عشان الـ ID يرجع متحدث سليم بعد كل يوم
      await result.fold((_) async {}, (prayerTimes) async {
        notificationId = await _schedulePrayersForDay(prayerTimes, notificationId);
      });
    }
  }

  Future<int> _schedulePrayersForDay(var prayerTimes, int currentId) async {
    final Map<String, int> iqamaDelays = await getIqamaDelaysUseCase.execute();
    final prayers = [
      (name: 'الفجر', time: prayerTimes.fajr, key: 'fajr'),
      (name: 'الشروق', time: prayerTimes.sunrise, key: 'shurooq'),
      (name: 'الظهر', time: prayerTimes.dhuhr, key: 'dhuhr'),
      (name: 'العصر', time: prayerTimes.asr, key: 'asr'),
      (name: 'المغرب', time: prayerTimes.maghrib, key: 'maghrib'),
      (name: 'العشاء', time: prayerTimes.isha, key: 'isha'),
    ];

    for (var prayer in prayers) {
      if (prayer.time != null && prayer.time!.isAfter(DateTime.now())) {
        
        if (prayer.key == 'shurooq') {
          continue; 
        }

        log("⏲️ Scheduling notification for prayer is: ${prayer.name} at ${prayer.time}");
        
        // --- جدولة الأذان ---
        await schedulePrayerUseCase.execute(
          id: currentId++, // 👈 هياخد الرقم ويزيد
          title: 'حان الآن موعد صلاة ${prayer.name}',
          body: prayer.name == 'الفجر'
              ? 'الصلاة خير من النوم'
              : 'حي على الصلاة، حي على الفلاح', // 👈 اتصلحت
          scheduledTime: prayer.time!,
          soundName: prayer.name == 'الفجر' ? 'fajr_azan' : 'adhan',
        );

        // --- جدولة الإقامة ---
        if ((iqamaDelays[prayer.key] ?? -1) > 0) {
          await schedulePrayerUseCase.execute(
            id: currentId++, // 👈 هياخد الرقم ويزيد
            title: 'إقامة صلاة ${prayer.name}',
            body: 'تجهز للصلاة، ستقام الصلاة الآن',
            scheduledTime: prayer.time!.add(
              Duration(minutes: iqamaDelays[prayer.key]!),
            ),
            soundName: 'iqama_sound',
          );
        }
      }
    }
    
    return currentId; 
  }

  Future<void> testNotification(int sound) async {
    print("⏳ جاري جدولة إشعار تجريبي بعد 5 ثواني...");

    await schedulePrayerUseCase.execute(
      id: 888,
      title: 'إشعار تجريبي 🚀',
      body: 'عاش يا هندسة! الإشعارات شغالة في الخلفية زي الفل.',
      scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
      soundName: sound == 2
          ? 'fajr_azan'
          : sound == 1
          ? 'adhan'
          : 'iqama_sound',
    );
  }
}
