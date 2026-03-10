import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hafiz_al_ahd/core/services/location_service.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/core/utils/calculation_method_helper.dart';

class PrayerTimesCubit extends Cubit<PrayerTimesStates> {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;
  final SaveLocationUseCase saveLocationUseCase;
  final GetCachedLocationUseCase getCachedLocationUseCase;
  final SchedulePrayerUseCase schedulePrayerUseCase;
  // 👈 إضافة الـ Cancel UseCase
  final CancelAllNotificationsUseCase cancelAllNotificationsUseCase;
  final GetIqamaDelaysUseCase getIqamaDelaysUseCase = GetIqamaDelaysUseCase();

  PrayerTimesCubit({
    required this.getPrayerTimesUseCase,
    required PrayerTimesInitial initialState,
    required this.saveLocationUseCase,
    required this.getCachedLocationUseCase,
    required this.schedulePrayerUseCase,
    // 👈 إضافته في الـ Constructor
    required this.cancelAllNotificationsUseCase,
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
        // 1. تحديث واجهة المستخدم
        emit(PrayerTimesLoaded(prayerTimes, city: city));

        // 2. 👈 السطر السحري: جدولة الإشعارات في كل الحالات
        _scheduleNotificationsForNext6Days(latitude, longitude, city ?? '');
      });
    } catch (e) {
      emit(PrayerTimesError(e.toString()));
    }
  }

  Future<void> fetchPrayerTimesByLocation() async {
    late Position position;
    try {
      emit(PrayerTimesLoading());
      position = await LocationService.determinePosition();
      LocationEntity locationDetails = await LocationService.getLocationDetails(
        position,
      );
      String cityName = locationDetails.city;

      String method = '3'; // Default method
      if (locationDetails.country != null) {
        method = CalculationMethodHelper.getMethodForCountry(
          locationDetails.country!,
        );
      }

      // حفظ الموقع الجديد في الكاش للمرات القادمة
      await saveLocationUseCase(
        LocationEntity(
          latitude: position.latitude,
          longitude: position.longitude,
          city: cityName,
          country: locationDetails.country, // Save country code if possible
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
      // بدلاً من إرسال خطأ فوراً، نحاول تحميل الكاش أولاً
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

    // نحفظ الموقع اللي اليوزر اختاره يدوياً في الكاش عشان المرات الجاية
    await saveLocationUseCase(
      LocationEntity(
        latitude: lat,
        longitude: lng,
        city: city,
        country: country,
      ),
    );

    // 👈 ننادي على الدالة الأساسية بدل الدالة اللي مسحناها
    await fetchPrayerTimes(
      latitude: lat,
      longitude: lng,
      date: DateTime.now(),
      city: city,
      country: country,
      method: method,
    );
  }

  // -------------------------------------------------------------------

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

      // 👈 ننادي على الدالة الأساسية بدل الدالة اللي مسحناها
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
    // 👈 يستحسن تغير اسم الدالة لـ 6 أيام
    double lat,
    double lng,
    String city,
  ) async {
    // 1. مسحنا الإشعارات القديمة
    await cancelAllNotificationsUseCase.execute();
    log(
      "Notifications cleared. Scheduling new notifications for the next 6 days......",
    );
    int notificationId = 0;

    // 2. سحبنا أرقام الإقامة من (المصدر الوحيد للحقيقة)
    final iqamaDelays = await getIqamaDelaysUseCase.execute();

    // 3. قللنا اللوب لـ 6 أيام عشان نتفادى الـ Crash بتاع الـ iOS (10 إشعارات في اليوم * 6 = 60)
    for (int i = 0; i < 6; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final result = await getPrayerTimesUseCase(
        latitude: lat,
        longitude: lng,
        date: date,
        city: city,
      );

      result.fold((_) {}, (prayerTimes) async {
        // ==================== الفجر ====================
        if (prayerTimes.fajr != null) {
          // أ. إشعار الأذان (بصوت الأذان)
          await schedulePrayerUseCase.execute(
            id: notificationId++,
            title: 'حان الآن موعد صلاة الفجر',
            body: 'الصلاة خير من النوم',
            scheduledTime: prayerTimes.fajr!,
            soundName: 'adhan',
          );

          // ب. إشعار الإقامة (بالرنة العادية)
          int delay = iqamaDelays['fajr'] ?? 25;
          if (delay > 0) {
            await schedulePrayerUseCase.execute(
              id: notificationId++,
              title: 'إقامة صلاة الفجر',
              body: 'تجهز للصلاة، ستقام الصلاة الآن',
              scheduledTime: prayerTimes.fajr!.add(Duration(minutes: delay)),
            );
          }
        }

        // ==================== الظهر ====================
        if (prayerTimes.dhuhr != null) {
          await schedulePrayerUseCase.execute(
            id: notificationId++,
            title: 'حان الآن موعد صلاة الظهر',
            body: 'حي على الصلاة، حي على الفلاح',
            scheduledTime: prayerTimes.dhuhr!,
            soundName: 'adhan',
          );

          int delay = iqamaDelays['dhuhr'] ?? 15;
          if (delay > 0) {
            await schedulePrayerUseCase.execute(
              id: notificationId++,
              title: 'إقامة صلاة الظهر',
              body: 'تجهز للصلاة، ستقام الصلاة الآن',
              scheduledTime: prayerTimes.dhuhr!.add(Duration(minutes: delay)),
            );
          }
        }

        // ==================== العصر ====================
        if (prayerTimes.asr != null) {
          await schedulePrayerUseCase.execute(
            id: notificationId++,
            title: 'حان الآن موعد صلاة العصر',
            body: 'حي على الصلاة، حي على الفلاح',
            scheduledTime: prayerTimes.asr!,
            soundName: 'adhan',
          );

          int delay = iqamaDelays['asr'] ?? 15;
          if (delay > 0) {
            await schedulePrayerUseCase.execute(
              id: notificationId++,
              title: 'إقامة صلاة العصر',
              body: 'تجهز للصلاة، ستقام الصلاة الآن',
              scheduledTime: prayerTimes.asr!.add(Duration(minutes: delay)),
            );
          }
        }

        // ==================== المغرب ====================
        if (prayerTimes.maghrib != null) {
          await schedulePrayerUseCase.execute(
            id: notificationId++,
            title: 'حان الآن موعد صلاة المغرب',
            body: 'حي على الصلاة، حي على الفلاح',
            scheduledTime: prayerTimes.maghrib!,
            soundName: 'adhan',
          );

          int delay = iqamaDelays['maghrib'] ?? 10;
          if (delay > 0) {
            await schedulePrayerUseCase.execute(
              id: notificationId++,
              title: 'إقامة صلاة المغرب',
              body: 'تجهز للصلاة، ستقام الصلاة الآن',
              scheduledTime: prayerTimes.maghrib!.add(Duration(minutes: delay)),
            );
          }
        }

        // ==================== العشاء ====================
        if (prayerTimes.isha != null) {
          await schedulePrayerUseCase.execute(
            id: notificationId++,
            title: 'حان الآن موعد صلاة العشاء',
            body: 'حي على الصلاة، حي على الفلاح',
            scheduledTime: prayerTimes.isha!,
            soundName: 'adhan',
          );

          int delay = iqamaDelays['isha'] ?? 15;
          if (delay > 0) {
            await schedulePrayerUseCase.execute(
              id: notificationId++,
              title: 'إقامة صلاة العشاء',
              body: 'تجهز للصلاة، ستقام الصلاة الآن',
              scheduledTime: prayerTimes.isha!.add(Duration(minutes: delay)),
            );
          }
        }
      });
    }
  }

  // -------------------------------------------------------------------
  // دالة مؤقتة لاختبار الإشعارات فوراً
  Future<void> testNotification() async {
    print("⏳ جاري جدولة إشعار تجريبي بعد 5 ثواني...");

    await schedulePrayerUseCase.execute(
      id: 999, // رقم مميز عشان ميتعارضش مع الصلوات
      title: 'إشعار تجريبي 🚀',
      body: 'عاش يا هندسة! الإشعارات شغالة في الخلفية زي الفل.',
      scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
    );
  }
}
