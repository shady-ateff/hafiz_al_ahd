import 'dart:developer';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/services/location_service.dart';
import 'package:hafiz_al_ahd/core/utils/home_widget_helper.dart';
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
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hijri/hijri_calendar.dart';

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

    log(
      "[prayer_cubit]Checking if we need to schedule background notifications...",
    );
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
    log("[prayer_cubit - _handleFetchResult] Fetching prayer times...");
    final result = await fetchOrchestrator.execute(
      lat: lat,
      lng: lng,
      city: city,
      country: country,
    );

    log("Fetch orchestrator completed. Processing result...");
    result.fold((failure) => emit(PrayerTimesError(failure.message)), (
      prayerTimes,
    ) {
      log("Prayer times fetched successfully.");
      emit(PrayerTimesLoaded(prayerTimes, city: city));
      _updateStickyCountdown(prayerTimes);
      // _checkBackgroundScheduling(lat, lng, city);
    });
  }

  Future<void> fetchPrayerTimesByLocation() async {
    try {
      emit(PrayerTimesLoading());
      final position = await LocationService.determinePosition();
      final details = await LocationService.getLocationDetails(position);

      log(
        "Fetching prayer times for location: ${details.city}, ${details.country} (lat: ${position.latitude}, lng: ${position.longitude})",
      );
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
    log(
      "Fetching prayer times for manually entered location: $city, $country (lat: $lat, lng: $lng)",
    );
    await _handleFetchResult(lat, lng, city, country);
  }

  Future<void> loadPrayerTimesFromCache() async {
    emit(PrayerTimesLoading());
    final result = await getCachedLocationUseCase();

    result.fold((failure) => emit(PrayerTimesNeedsManualLocation()), (loc) {
      log(
        "No location from GPS, but found cached location: ${loc.city}, ${loc.country}. Fetching prayer times for cached location...",
      );
      return _handleFetchResult(
        loc.latitude,
        loc.longitude,
        loc.city,
        loc.country,
      );
    });
  }

  // -------------------------------------------------------------------
  // دالة العداد الثابت (Sticky Notification)
  // -------------------------------------------------------------------
  Future<void> _updateStickyCountdown(var prayerTimes) async {
    // 1. نجلب إعدادات تأخير الإقامة من الكاش بسرعة
    final iqamaDelaysUseCase =
        sl<GetIqamaDelaysUseCase>(); // تأكد من استدعاء sl
    final iqamaDelays = await iqamaDelaysUseCase.execute();

    // 2. نحسب الصلاة القادمة (مدمج معها حالة الإقامة)
    final nextPrayer = prayerTimes.getNextPrayer(
      DateTime.now(),
      iqamaDelays: iqamaDelays,
    );

    // 3. تحديث الإشعار الثابت (Sticky Notification)
    if (nextPrayer.time != null) {
      await showStickyNotificationUseCase.execute(
        id: 999,
        title: nextPrayer.isIqama
            ? 'الإقامة القادمة: ${nextPrayer.name}'
            : 'الصلاة القادمة: ${nextPrayer.name}',
        body: nextPrayer.isIqama
            ? 'متبقي على إقامة الصلاة'
            : 'متبقي على رفع الأذان',
        nextPrayerTime: nextPrayer.time!,
      );
    }

    // 4. 👈 السطر السحري: تحديث الويدجت الخارجية (App Widget)
    String locationName = "غير محدد";
    final locResult = await getCachedLocationUseCase();
    locResult.fold((l) => null, (loc) {
      locationName = '${loc.city}، ${loc.country}';
      _checkBackgroundScheduling(loc.latitude, loc.longitude, loc.city);
    });
    final hijriDate = HijriCalendar.now().toFormat("dd MMMM yyyy");

    await updateNativeWidgets(nextPrayer, prayerTimes, locationName, hijriDate);

    if (nextPrayer.time != null) {
      await scheduleNextAlarm(nextPrayer.time!, prayerTimes, iqamaDelays);
    }

  }

  // -------------------------------------------------------------------
  // عملية الجدولة الفورية (تستخدم عند تغيير إعدادات الإقامة أو الإشعارات)
  // -------------------------------------------------------------------
  Future<void> forceReschedule() async {
    final locationResult = await getCachedLocationUseCase();
    fetchPrayerTimesByLocation();
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
        log(
          '[Restoring sticky notification] Fetching prayer times in the background for ${location.city}, ${location.country}...',
        );
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

  /// 👈 اختبار الأذان: بيستخدم باكيدج alarm للأذان والإشعارات العادية للإقامة
  Future<void> testNotification(int sound) async {
    print("⏳ جاري جدولة إشعار تجريبي بعد 5 ثواني...");

    final notificationRepository = sl<BaseNotificationRepository>();
    final pref = sl<SharedPreferences>();
    final double adhanVolume = pref.getDouble('adhan_volume') ?? 1.0;

    if (sound == 1 || sound == 2) {
      // 👈 أذان أو أذان الفجر — بنستخدم باكيدج alarm
      await notificationRepository.scheduleAdhanAlarm(
        id: 888,
        title: 'إشعار تجريبي 🚀',
        body: 'عاش يا هندسة! الأذان شغال بباكيدج alarm المحمي.',
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
        assetAudioPath: sound == 2
            ? 'assets/sounds/fajr_azan.mp3'
            : 'assets/sounds/adhan.mp3',
        volume: adhanVolume,
      );
    } else {
      // 👈 إقامة — لسه بتستخدم الإشعارات العادية
      await schedulePrayerUseCase.execute(
        id: 888,
        title: 'إشعار تجريبي 🚀',
        body: 'عاش يا هندسة! الإشعارات شغالة في الخلفية زي الفل.',
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)),
        soundName: 'iqama_sound',
      );
    }
  }
}

