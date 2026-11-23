import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/DI/service_locator.dart';
import '../../../domain/entities/focus_schedule.dart';
import '../../../domain/entities/focus_ward_type.dart';
import '../../../domain/entities/quran_reading_goal.dart';
import '../../../domain/repositories/focus_app_exemption_repository.dart';
import '../../../domain/repositories/focus_schedule_repository.dart';
import '../../../domain/services/focus_schedule_coordinator.dart';
import '../../../domain/services/focus_session_coordinator.dart';
import '../../../domain/services/focus_session_recovery_manager.dart';
import 'focus_settings_state.dart';

class FocusSettingsCubit extends Cubit<FocusSettingsState> {
  static const String kFocusModeMasterEnabledKey = 'focus_mode_master_enabled';

  final FocusScheduleCoordinator scheduleCoordinator;
  final FocusSessionCoordinator sessionCoordinator;
  final FocusScheduleRepository scheduleRepository;
  final FocusAppExemptionRepository appExemptionRepository;
  final FocusSessionRecoveryManager recoveryManager;
  final SharedPreferences? _prefs;

  FocusSettingsCubit({
    required this.scheduleCoordinator,
    required this.sessionCoordinator,
    required this.scheduleRepository,
    required this.appExemptionRepository,
    required this.recoveryManager,
    SharedPreferences? prefs,
  })  : _prefs = prefs,
        super(const FocusSettingsState());

  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs;
    if (sl.isRegistered<SharedPreferences>()) {
      return sl<SharedPreferences>();
    }
    return await SharedPreferences.getInstance();
  }

  Future<void> loadSettings() async {
    emit(state.copyWith(isLoading: true));
    try {
      final p = await _getPrefs();
      final isMasterEnabled = p.getBool(kFocusModeMasterEnabledKey) ?? false;

      // 1. Reconcile active session and native service state
      await recoveryManager.reconcileAndRecover();
      final activeSession = sessionCoordinator.state;

      // 2. Load schedules or seed defaults if fresh installation
      var schedules = await scheduleRepository.getAllSchedules();
      if (schedules.isEmpty) {
        schedules = await _seedDefaultSchedules();
      }

      // 3. Load exempt app count
      final exemptPackages = await appExemptionRepository.getExemptPackageNames();

      emit(state.copyWith(
        isFocusModeMasterEnabled: isMasterEnabled,
        schedules: schedules,
        activeSession: activeSession.isEnforcing ? activeSession : null,
        clearActiveSession: !activeSession.isEnforcing,
        exemptAppsCount: exemptPackages.length,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'فشل تحميل إعدادات وضع التركيز',
      ));
    }
  }

  Future<void> toggleMasterSwitch(bool isEnabled) async {
    try {
      final p = await _getPrefs();
      await p.setBool(kFocusModeMasterEnabledKey, isEnabled);
      emit(state.copyWith(isFocusModeMasterEnabled: isEnabled));

      if (!isEnabled) {
        await scheduleCoordinator.cancelAllSchedules();
        if (state.hasActiveSession) {
          await sessionCoordinator.cancelSession();
          emit(state.copyWith(clearActiveSession: true));
        }
      } else {
        await scheduleCoordinator.syncAllSchedules();
      }
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل تعديل حالة وضع التركيز'));
    }
  }

  Future<void> toggleSchedule(String scheduleId, bool isEnabled) async {
    try {
      if (isEnabled) {
        await scheduleCoordinator.enableSchedule(scheduleId);
      } else {
        await scheduleCoordinator.disableSchedule(scheduleId);
      }

      final updatedSchedules = await scheduleRepository.getAllSchedules();
      emit(state.copyWith(schedules: updatedSchedules));
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل تعديل حالة الجدول'));
    }
  }

  Future<void> updateScheduleTime(
      String scheduleId, int hour, int minute) async {
    try {
      final schedule = await scheduleRepository.getScheduleById(scheduleId);
      if (schedule != null) {
        final updated = schedule.copyWith(
          hour: hour,
          minute: minute,
          updatedAt: DateTime.now(),
        );
        await scheduleCoordinator.addOrUpdateSchedule(updated);

        final updatedSchedules = await scheduleRepository.getAllSchedules();
        emit(state.copyWith(schedules: updatedSchedules));
      }
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل تعديل موعد الورد'));
    }
  }

  Future<void> updateScheduleQuranGoal(String scheduleId, int pages) async {
    try {
      final schedule = await scheduleRepository.getScheduleById(scheduleId);
      if (schedule != null) {
        final updated = schedule.copyWith(
          targetQuranGoal: QuranReadingGoal.pageCount(pages),
          updatedAt: DateTime.now(),
        );
        await scheduleCoordinator.addOrUpdateSchedule(updated);

        final p = await _getPrefs();
        await p.setInt('focus_quran_target_pages', pages);

        final updatedSchedules = await scheduleRepository.getAllSchedules();
        emit(state.copyWith(schedules: updatedSchedules));
      }
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل تعديل عدد صفحات الورد'));
    }
  }

  Future<void> snoozeActiveSession() async {
    try {
      final snoozed = await sessionCoordinator.snoozeSession();
      if (snoozed) {
        emit(state.copyWith(activeSession: sessionCoordinator.state));
      } else {
        emit(state.copyWith(
            errorMessage: 'لا يمكن تأجيل الجلسة أكثر من مرتين'));
      }
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل تأجيل الجلسة'));
    }
  }

  Future<void> cancelActiveSession() async {
    try {
      await sessionCoordinator.cancelSession();
      emit(state.copyWith(clearActiveSession: true));
    } catch (_) {
      emit(state.copyWith(errorMessage: 'فشل إلغاء الجلسة'));
    }
  }

  Future<List<FocusSchedule>> _seedDefaultSchedules() async {
    final now = DateTime.now();
    final defaults = [
      FocusSchedule.daily(
        id: 'default_morning_adhkar',
        wardType: FocusWardType.morningAzkar,
        title: 'أذكار الصباح',
        hour: 6,
        minute: 30,
        isEnabled: false,
        now: now,
      ),
      FocusSchedule.daily(
        id: 'default_evening_adhkar',
        wardType: FocusWardType.eveningAzkar,
        title: 'أذكار المساء',
        hour: 17,
        minute: 0,
        isEnabled: false,
        now: now,
      ),
      FocusSchedule.daily(
        id: 'default_quran_reading',
        wardType: FocusWardType.quranReading,
        title: 'ورد القرآن الكريم',
        hour: 21,
        minute: 0,
        isEnabled: false,
        targetQuranGoal: QuranReadingGoal.pageCount(2),
        now: now,
      ),
    ];

    for (final schedule in defaults) {
      await scheduleCoordinator.addOrUpdateSchedule(schedule);
    }

    return await scheduleRepository.getAllSchedules();
  }
}
