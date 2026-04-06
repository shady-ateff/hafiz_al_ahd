import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_permission.dart';
import 'package:hafiz_al_ahd/features/onboarding/presentation/cubit/onboarding_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit() : super(OnboardingInitial());

  int currentPage = 0;
  static const _key = 'isOnboardingComplete';

  /// التحقق إذا كان اليوزر خلص الـ Onboarding قبل كده
  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// طلب الصلاحية المناسبة حسب الخطوة الحالية
  Future<PermissionResult> requestCurrentPermission() async {
    switch (currentPage) {
      case 0:
        return await PermissionManager.requestLocation();
      case 1:
        return await PermissionManager.requestNotification();
      case 2:
        return await PermissionManager.requestExactAlarm();
      case 3:
        return await PermissionManager.requestBatteryOptimization();
      default:
        return PermissionResult.denied;
    }
  }

  /// الانتقال للصفحة التالية
  void nextPage() {
    if (currentPage < 3) {
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
    if (page >= 0 && page <= 3) {
      currentPage = page;
      emit(OnboardingPageChanged(currentPage));
    }
  }

  /// حفظ حالة الانتهاء والانتقال للشاشة الرئيسية
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    emit(OnboardingComplete());
  }
}
