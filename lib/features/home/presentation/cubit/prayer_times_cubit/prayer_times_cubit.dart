import 'dart:developer';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hafiz_al_ahd/core/services/location_service.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/fetch_prayer_times_orchestrator_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/check_if_scheduling_needed_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/check_location_change_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/show_sticky_notification_usecase.dart';
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';

class PrayerTimesCubit extends Cubit<PrayerTimesStates> {
  // 1. الـ UseCases الخاصة بالـ UI والمواقيت
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final FetchPrayerTimesOrchestrator
  fetchOrchestrator; // 👈 الـ UseCase العملاق
  final SaveLocationUseCase saveLocationUseCase;
  final GetCachedLocationUseCase getCachedLocationUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  final ShowStickyNotificationUseCase showStickyNotificationUseCase;
  final CheckLocationChangeUseCase checkLocationChangeUseCase;
  final CheckIfSchedulingNeededUseCase checkIfSchedulingNeededUseCase;
  final ScheduleWeeklyPrayersUseCase scheduleWeeklyPrayersUseCase;

  PrayerTimesCubit({
    required this.getPrayerTimesUseCase,
    required this.saveLocationUseCase,
    required this.getCachedLocationUseCase,
    required this.showStickyNotificationUseCase,
    required this.checkLocationChangeUseCase,
    required this.checkIfSchedulingNeededUseCase,
    required this.scheduleWeeklyPrayersUseCase,
    required this.schedulePrayerUseCase,
    required this.cancelAllNotificationsUseCase,
    required this.fetchOrchestrator,
  }) : super(
         PrayerTimesInitial(),
       ); // شيلنا الـ initialState من الـ constructor عشان ملهاش لازمة تتبعت من الـ locator

  void _checkBackgroundScheduling(double lat, double lng, String city) async {
    final locationChanged = await checkLocationChangeUseCase.execute();
    if (locationChanged) emit(PrayerTimesLocationChanged());

    if (checkIfSchedulingNeededUseCase.execute()) {
      scheduleWeeklyPrayersUseCase.execute(lat, lng, city);
    }
  }

  Future<void> _handleFetchResult(
    double lat,
    double lng,
    String city,
    String? country,
  ) async {
    final result = await fetchOrchestrator.execute(
      lat: lat,
      lng: lng,
      city: city,
      country: country,
    );

    result.fold((failure) => emit(PrayerTimesError(failure.message)), (
      prayerTimes,
    ) {
      emit(PrayerTimesLoaded(prayerTimes, city: city));
      _updateStickyCountdown(prayerTimes);
      _checkBackgroundScheduling(lat, lng, city);
    });
  }

  Future<void> fetchPrayerTimesByLocation() async {
    try {
      emit(PrayerTimesLoading());
      final position = await LocationService.determinePosition();
      final details = await LocationService.getLocationDetails(position);

      await _handleFetchResult(
        position.latitude,
        position.longitude,
        details.city,
        details.country,
      );
    } catch (e) {
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
    await _handleFetchResult(lat, lng, city, country);
  }

  Future<void> loadPrayerTimesFromCache() async {
    emit(PrayerTimesLoading());
    final result = await getCachedLocationUseCase();

    result.fold(
      (failure) => emit(PrayerTimesNeedsManualLocation()),
      (loc) => _handleFetchResult(
        loc.latitude,
        loc.longitude,
        loc.city,
        loc.country,
      ),
    );
  }

  // -------------------------------------------------------------------
  //  المايسترو: الدالة الرئيسية اللي بتشتغل أول ما التطبيق يفتح
  // -------------------------------------------------------------------
  // Future<void> initAppAndCheckPrayers(
  //   double lat,
  //   double lng,
  //   String city,
  // ) async {
  //   // 1. هل المكان اتغير بمسافة كبيرة؟
  //   final locationChanged = await checkLocationChangeUseCase.execute();
  //   if (locationChanged) {
  //     // بنبعت State للـ UI عشان يطلع رسالة لليوزر يطلب منه تحديث المكان
  //     emit(PrayerTimesLocationChanged());
  //   }

  //   // 2. هل إحنا محتاجين نجدول إشعارات 6 أيام؟ (هترد في جزء من الثانية من الكاش)
  //   final needsScheduling = checkIfSchedulingNeededUseCase.execute();
  //   if (needsScheduling) {
  //     log("⏳ بدء عملية جدولة الإشعارات للـ 6 أيام القادمة في الخلفية...");
  //     // بنشغلها في الخلفية من غير ما نوقف الـ UI (ممكن تحط await لو عايز تظهر Loading)
  //     scheduleWeeklyPrayersUseCase.execute(lat, lng, city).then((_) {
  //       log("✅ تمت الجدولة بنجاح!");
  //     });
  //   }
  // }

  // -------------------------------------------------------------------
  // جلب مواقيت اليوم لعرضها في الشاشة الرئيسية (UI)
  // -------------------------------------------------------------------
  // Future<void> fetchPrayerTimes({
  //   required double latitude,
  //   required double longitude,
  //   required DateTime date,
  //   String? city,
  //   String? country,
  //   String? method,
  // }) async {
  //   emit(PrayerTimesLoading());
  //   try {
  //     final result = await getPrayerTimesUseCase(
  //       latitude: latitude,
  //       longitude: longitude,
  //       date: date,
  //       city: city,
  //       country: country,
  //       method: method,
  //     );

  //     result.fold((failure) => emit(PrayerTimesError(failure.message)), (
  //       prayerTimes,
  //     ) {
  //       emit(PrayerTimesLoaded(prayerTimes, city: city));

  //       // تشغيل العداد الثابت للصلاة القادمة
  //       _updateStickyCountdown(prayerTimes);
  //     });
  //   } catch (e) {
  //     emit(PrayerTimesError(e.toString()));
  //   }
  // }

  // -------------------------------------------------------------------
  // دالة العداد الثابت (Sticky Notification)
  // -------------------------------------------------------------------
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
      nextTime = prayerTimes.fajr!.add(const Duration(days: 1));
      nextName = 'الفجر';
    }

    if (nextTime != null) {
      await showStickyNotificationUseCase.execute(
        id: 999,
        title: 'الصلاة القادمة: $nextName',
        body: 'متبقي على رفع الأذان',
        nextPrayerTime: nextTime,
      );
    }
  }

  // -------------------------------------------------------------------
  // دوال الـ GPS والـ Cache (لم تتغير، فقط نضفنا ترتيبها)
  // -------------------------------------------------------------------
  // Future<void> fetchPrayerTimesByLocation() async {
  //   late Position position;
  //   try {
  //     emit(PrayerTimesLoading());
  //     position = await LocationService.determinePosition();
  //     LocationEntity locationDetails = await LocationService.getLocationDetails(
  //       position,
  //     );
  //     String cityName = locationDetails.city;

  //     String method = '3';
  //     if (locationDetails.country != null) {
  //       method = CalculationMethodHelper.getMethodForCountry(
  //         locationDetails.country!,
  //       );
  //     }

  //     await saveLocationUseCase(
  //       LocationEntity(
  //         latitude: position.latitude,
  //         longitude: position.longitude,
  //         city: cityName,
  //         country: locationDetails.country,
  //       ),
  //     );

  //     await fetchPrayerTimes(
  //       latitude: position.latitude,
  //       longitude: position.longitude,
  //       date: DateTime.now(),
  //       city: cityName,
  //       country: locationDetails.country,
  //       method: method,
  //     );

  //     // نبلغ المايسترو يتأكد من الجدولة
  //     initAppAndCheckPrayers(position.latitude, position.longitude, cityName);
  //   } catch (e) {
  //     print("GPS Failed, loading from Cache... Error was: ${e.toString()}");
  //     await loadPrayerTimesFromCache();
  //   }
  // }

  // Future<void> fetchPrayerTimesManually(
  //   double lat,
  //   double lng,
  //   String city, [
  //   String? country,
  // ]) async {
  //   emit(PrayerTimesLoading());

  //   String method = '3';
  //   if (country != null) {
  //     method = CalculationMethodHelper.getMethodForCountry(country);
  //   }

  //   await saveLocationUseCase(
  //     LocationEntity(
  //       latitude: lat,
  //       longitude: lng,
  //       city: city,
  //       country: country,
  //     ),
  //   );

  //   await fetchPrayerTimes(
  //     latitude: lat,
  //     longitude: lng,
  //     date: DateTime.now(),
  //     city: city,
  //     country: country,
  //     method: method,
  //   );
  // }

  // Future<void> loadPrayerTimesFromCache() async {
  //   emit(PrayerTimesLoading());

  //   final result = await getCachedLocationUseCase();

  //   result.fold((failure) => emit(PrayerTimesNeedsManualLocation()), (
  //     location,
  //   ) async {
  //     String method = '3';
  //     if (location.country != null) {
  //       method = CalculationMethodHelper.getMethodForCountry(location.country!);
  //     }

  //     await fetchPrayerTimes(
  //       latitude: location.latitude,
  //       longitude: location.longitude,
  //       date: DateTime.now(),
  //       city: location.city,
  //       country: location.country,
  //       method: method,
  //     );

  //     // نبلغ المايسترو يتأكد من الجدولة
  //     initAppAndCheckPrayers(
  //       location.latitude,
  //       location.longitude,
  //       location.city,
  //     );
  //   });
  // }

  // -------------------------------------------------------------------
  // عملية الجدولة الفورية (تستخدم عند تغيير إعدادات الإقامة أو الإشعارات)
  // -------------------------------------------------------------------
  Future<void> forceReschedule() async {
    final locationResult = await getCachedLocationUseCase();
    locationResult.fold(
      (failure) => log("No cached location found to reschedule!"),
      (location) async {
        log("🔄 إجبار مسح وإعادة الجدولة لجميع الإشعارات...");
        await cancelAllNotificationsUseCase.execute();
        await scheduleWeeklyPrayersUseCase.execute(
          location.latitude,
          location.longitude,
          location.city,
        );
        restoreStickyNotificationIfNeeded();
      },
    );
  }

  // داخل PrayerTimesCubit
  Future<void> restoreStickyNotificationIfNeeded() async {
    // 1. هل المواقيت موجودة أصلاً في الشاشة؟ (التطبيق كان في الخلفية ورجع)
    if (state is PrayerTimesLoaded) {
      final currentPrayerTimes = (state as PrayerTimesLoaded).prayerTimes;
      await _updateStickyCountdown(currentPrayerTimes);
      return; // 👈 اخرج فوراً، مفيش داعي نكلم الداتا بيز تاني!
    }

    // 2. لو المواقيت مش موجودة (التطبيق كان مقتول من الميموري ولسة بيقوم)
    final locationResult = await getCachedLocationUseCase();

    locationResult.fold(
      (failure) => null, // مفيش لوكيشن؟ خلاص متعملش حاجة
      (location) async {
        // نستخدم الـ Orchestrator اللي عملناه عشان نجيب المواقيت "في صمت"
        final result = await fetchOrchestrator.execute(
          lat: location.latitude,
          lng: location.longitude,
          city: location.city,
          country: location.country,
        );

        result.fold(
          (failure) => null, // لو حصل خطأ في جلب المواقيت نسكت ومفيش كراش
          (prayerTimes) async {
            // لو المواقيت جت سليمة، نحدث الإشعار
            await _updateStickyCountdown(prayerTimes);
          },
        );
      },
    );
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
