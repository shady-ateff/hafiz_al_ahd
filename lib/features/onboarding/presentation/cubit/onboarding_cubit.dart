import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_permission.dart';
import 'package:hafiz_al_ahd/features/onboarding/presentation/cubit/onboarding_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class OnboardingCubit extends Cubit<OnboardingState> {
  final List<PermissionType> requiredPermissions;

  OnboardingCubit({required this.requiredPermissions}) : super(OnboardingInitial());

  int currentPage = 0;
  static const _key = 'isOnboardingComplete';

  /// التحقق إذا كان اليوزر خلص كل خطوات الـ Onboarding المطلوبة
  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    
    // قائمة الصلاحيات الأساسية
    final requiredTypes = [
      PermissionType.location,
      PermissionType.notification,
      PermissionType.exactAlarm,
      PermissionType.batteryOptimization,
    ];

    try {
      // ignore: undefined_identifier
      if (await isAutoStartAvailable == true) {
        requiredTypes.add(PermissionType.autoStart);
      }
    } catch (_) {}

    // تجاهل خطأ عدم وجود DeviceInfoPlugin هنا لتبسيط الشيك،
    // سيتم فحصه بدقة في شاشة الـ Onboarding نفسها.

    for (final type in requiredTypes) {
      if (!(prefs.getBool('onboarding_step_${type.name}') ?? false)) {
        return false;
      }
    }
    return true;
  }

  /// تسجيل خطوة معينة على إنها اكتملت
  Future<void> markStepAsComplete(PermissionType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_step_${type.name}', true);
  }

  /// طلب الصلاحية المناسبة حسب الخطوة الحالية
  Future<PermissionResult> requestCurrentPermission() async {
    final type = requiredPermissions[currentPage];
    
    switch (type) {
      case PermissionType.location:
        return await PermissionManager.requestLocation();
      case PermissionType.notification:
        return await PermissionManager.requestNotification();
      case PermissionType.exactAlarm:
        return await PermissionManager.requestExactAlarm();
      case PermissionType.batteryOptimization:
        return await PermissionManager.requestBatteryOptimization();
      case PermissionType.autoStart:
        return await PermissionManager.requestAutoStart();
      case PermissionType.xiaomiCustom:
        return await PermissionManager.requestXiaomiPermissions();
    }
  }

  /// الانتقال للصفحة التالية
  void nextPage() {
    if (currentPage < requiredPermissions.length - 1) {
      currentPage++;
      emit(OnboardingPageChanged(currentPage));
    } else {
      completeOnboarding();
    }
  }

  /// الرجوع للصفحة السابقة
  void previousPage() {
    if (currentPage > 0) {
      currentPage--;
      emit(OnboardingPageChanged(currentPage));
    }
  }

  /// الانتقال لصفحة معينة (عند السحب يدوياً)
  void goToPage(int page) {
    if (page >= 0 && page < requiredPermissions.length) {
      currentPage = page;
      emit(OnboardingPageChanged(currentPage));
    }
  }

  /// حفظ حالة الانتهاء والانتقال للشاشة الرئيسية
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    await prefs.setBool('isAdhanEnabled', true);
    await prefs.setBool('isIqamaEnabled', true);

    // 3. 👈 إعادة تهيئة الإضافات عشان تحس بالصلاحيات الجديدة اللي لسه واخدينها
    // (لو عندك دالة بتجمع التهيئة دي في ملف الـ DI أو الـ main نادي عليها هنا)
    try {
      // مثال:
      await AndroidAlarmManager.initialize();
      // await sl<NotificationHelper>().init();
    } catch (e) {
      // تجاهل لو متعملهاش تهيئة مرتين
    }
    emit(OnboardingComplete());
  }
}
