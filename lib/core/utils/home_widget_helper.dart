import 'dart:developer';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart' as di;
import 'package:hafiz_al_ahd/features/home/domain/entities/next_pray_time.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hafiz_al_ahd/core/services/native_alarm_service.dart';
import 'package:hijri/hijri_calendar.dart';


@pragma('vm:entry-point')
Future<void> backgroundPrayerUpdater() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!di.sl.isRegistered<GetCachedLocationUseCase>()) {
    await di.init();
  }

  try {
    final sl = di.sl;

    // 1. جلب البيانات الأساسية مرة واحدة فقط
    final locationResult = await sl<GetCachedLocationUseCase>().call();
    final iqamaDelays = await sl<GetIqamaDelaysUseCase>().execute();

    locationResult.fold((failure) => log('Background: No Location cached'), (
      location,
    ) async {
      final prayerTimesResult = await sl<GetPrayerTimesUseCase>().call(
        latitude: location.latitude,
        longitude: location.longitude,
        date: DateTime.now(),
      );

      prayerTimesResult.fold(
        (failure) => log('Background: Failed to fetch prayer times'),
        (times) async {
          // 2. حساب الصلاة القادمة
          final nextPrayer = times.getNextPrayer(
            DateTime.now(),
            iqamaDelays: iqamaDelays,
          );

          // 3. نبعت الداتا الجاهزة لدالة التحديث (بدون إعادة جلب)
          final hijriDate = HijriCalendar.now().toFormat("dd MMMM yyyy");
          await updateNativeWidgets(
            nextPrayer,
            times,
            '${location.city}، ${location.country}',
            hijriDate,
          );

          // 4. جدولة الصلاة القادمة (الاستمرار في السلسلة)
          if (nextPrayer.time != null) {
            await scheduleNextAlarm(nextPrayer.time!, times, iqamaDelays);
            log('Background: Next alarm scheduled at ${nextPrayer.time}');
          }
        },
      );
    });
  } catch (e) {
    log('Background Task Critical Error: $e');
  }
}

String formatTimeArabic(DateTime time) {
  final int hour = time.hour;
  final int minute = time.minute;
  final String amPm = hour < 12 ? 'ص' : 'م';
  final int hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

  final String minuteStr = minute.toString().padLeft(2, '0');
  final String hourStr = hour12.toString().padLeft(2, '0');

  return '$hourStr:$minuteStr $amPm';
}

// 👈 دالة التحديث بقت "خفيفة" جداً لأنها بتستلم الداتا جاهزة
Future<void> updateNativeWidgets(
  NextPrayerTime next,
  PrayerTimesEntity allTimes,
  String locationName,
  String hijriDate,
) async {
  // بيانات الصلاة القادمة
  await HomeWidget.saveWidgetData<String>('next_prayer_name', next.name);
  await HomeWidget.saveWidgetData<String>('location_name', locationName);
  await HomeWidget.saveWidgetData<String>('hijri_date', hijriDate);
  await HomeWidget.saveWidgetData<String>(
    'next_prayer_time',
    formatTimeArabic(next.time!),
  );
  await HomeWidget.saveWidgetData<int>(
    'next_prayer_millis',
    next.time!.millisecondsSinceEpoch,
  );

  // بيانات جدول الصلوات بالكامل (Timeline)
  await HomeWidget.saveWidgetData<String>(
    'fajr_time',
    formatTimeArabic(allTimes.fajr!),
  );
  await HomeWidget.saveWidgetData<String>(
    'dhuhr_time',
    formatTimeArabic(allTimes.dhuhr!),
  );
  await HomeWidget.saveWidgetData<String>(
    'asr_time',
    formatTimeArabic(allTimes.asr!),
  );
  await HomeWidget.saveWidgetData<String>(
    'maghrib_time',
    formatTimeArabic(allTimes.maghrib!),
  );
  await HomeWidget.saveWidgetData<String>(
    'isha_time',
    formatTimeArabic(allTimes.isha!),
  );

  // تحديث الويدجت فعلياً في الأندرويد
  await HomeWidget.updateWidget(
    name: 'PrayerWidgetProvider',
    androidName: 'PrayerWidgetProvider',
  );
}

Future<void> scheduleNextAlarm(
  DateTime targetTime,
  PrayerTimesEntity allTimes,
  Map<String, int> iqamaDelays,
) async {
  // 1. حساب أقرب صلاة بعد الصلاة دي عشان نمررها للـ Native Receiver يقوم بتحديثها في الـ Widget والـ Notification بدون تأخير
  final nextNextPrayer = allTimes.getNextPrayer(
    targetTime.add(const Duration(minutes: 1)),
    iqamaDelays: iqamaDelays,
  );

  if (nextNextPrayer.time != null) {
    await NativeAlarmService.scheduleNativeSyncAlarm(
      triggerTimeMillis: targetTime.millisecondsSinceEpoch,
      notificationId: 999,
      notificationTitle: nextNextPrayer.isIqama
          ? 'الإقامة القادمة: ${nextNextPrayer.name}'
          : 'الصلاة القادمة: ${nextNextPrayer.name}',
      notificationBody: nextNextPrayer.isIqama
          ? 'متبقي على إقامة الصلاة'
          : 'متبقي على رفع الأذان',
      nextPrayerName: nextNextPrayer.name,
      nextPrayerTime: formatTimeArabic(nextNextPrayer.time!),
      nextPrayerMillis: nextNextPrayer.time!.millisecondsSinceEpoch,
      fajrTime: formatTimeArabic(allTimes.fajr!),
      dhuhrTime: formatTimeArabic(allTimes.dhuhr!),
      asrTime: formatTimeArabic(allTimes.asr!),
      maghribTime: formatTimeArabic(allTimes.maghrib!),
      ishaTime: formatTimeArabic(allTimes.isha!),
    );
  }

  // 2. بنزود ثانية عشان نتفادى مشاكل الـ Precision ونخلي Dart يكمل جدولته
  final scheduleTime = targetTime.add(const Duration(seconds: 1));

  await AndroidAlarmManager.oneShotAt(
    scheduleTime,
    199,
    backgroundPrayerUpdater,
    exact: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}
