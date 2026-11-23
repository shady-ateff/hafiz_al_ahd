import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_schedule_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_scheduling_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_schedule_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_schedule_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_recovery_manager.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_settings/focus_settings_cubit.dart';

class MockEnforcementPort implements FocusEnforcementPort {
  FocusEnforcementStatus status = FocusEnforcementStatus.stopped();

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async {
    status = FocusEnforcementStatus(
      isRunning: true,
      sessionId: sessionId,
      wardTitle: wardTitle,
      state: NativeEnforcementState.active,
      snoozeRemaining: 2,
    );
    return true;
  }

  @override
  Future<bool> stopEnforcement() async {
    status = FocusEnforcementStatus.stopped();
    return true;
  }

  @override
  Future<bool> isEnforcing() async => status.isRunning;

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async => status;
}

void main() {
  late FocusScheduleRepositoryImpl scheduleRepo;
  late FocusAppExemptionRepositoryImpl appExemptionRepo;
  late FocusSessionRepositoryImpl sessionRepo;
  late FocusScheduleCoordinator scheduleCoordinator;
  late FocusSessionCoordinator sessionCoordinator;
  late FocusSessionRecoveryManager recoveryManager;
  late MockEnforcementPort enforcementPort;
  late FocusSettingsCubit cubit;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    scheduleRepo = FocusScheduleRepositoryImpl(
      localDataSource: FocusScheduleLocalDataSourceImpl.inMemory(),
    );
    appExemptionRepo = FocusAppExemptionRepositoryImpl(
      localDataSource: FocusAppExemptionLocalDataSourceImpl.inMemory(),
    );
    sessionRepo = FocusSessionRepositoryImpl(
      localDataSource: FocusSessionLocalDataSourceImpl.inMemory(),
    );
    enforcementPort = MockEnforcementPort();

    scheduleCoordinator = FocusScheduleCoordinator(
      repository: scheduleRepo,
      schedulingPort: InMemoryFocusSchedulingPort(),
    );

    sessionCoordinator = FocusSessionCoordinator(
      adhkarPort: InMemoryAdhkarCompletionPort(),
      quranPort: InMemoryQuranReadingCompletionPort(),
      enforcementPort: enforcementPort,
      repository: sessionRepo,
    );

    recoveryManager = FocusSessionRecoveryManager(
      repository: sessionRepo,
      enforcementPort: enforcementPort,
    );

    cubit = FocusSettingsCubit(
      scheduleCoordinator: scheduleCoordinator,
      sessionCoordinator: sessionCoordinator,
      scheduleRepository: scheduleRepo,
      appExemptionRepository: appExemptionRepo,
      recoveryManager: recoveryManager,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('FocusSettingsCubit Tests', () {
    test('loadSettings seeds default schedules (Morning, Evening, Quran) if empty', () async {
      expect((await scheduleRepo.getAllSchedules()).isEmpty, isTrue);

      await cubit.loadSettings();

      expect(cubit.state.schedules.length, 3);
      final titles = cubit.state.schedules.map((s) => s.title).toList();
      expect(titles, contains('أذكار الصباح'));
      expect(titles, contains('أذكار المساء'));
      expect(titles, contains('ورد القرآن الكريم'));
      expect(cubit.state.isLoading, isFalse);
    });

    test('toggleSchedule updates enabled state', () async {
      await cubit.loadSettings();
      final scheduleId = cubit.state.schedules.first.id;

      await cubit.toggleSchedule(scheduleId, false);

      final updated = cubit.state.schedules.firstWhere((s) => s.id == scheduleId);
      expect(updated.isEnabled, isFalse);

      await cubit.toggleSchedule(scheduleId, true);
      final reEnabled = cubit.state.schedules.firstWhere((s) => s.id == scheduleId);
      expect(reEnabled.isEnabled, isTrue);
    });

    test('updateScheduleTime updates hour and minute of schedule', () async {
      await cubit.loadSettings();
      final scheduleId = cubit.state.schedules.first.id;

      await cubit.updateScheduleTime(scheduleId, 8, 45);

      final updated = cubit.state.schedules.firstWhere((s) => s.id == scheduleId);
      expect(updated.hour, 8);
      expect(updated.minute, 45);
    });

    test('snoozeActiveSession respects max 2 snoozes and records remaining count', () async {
      // Start an active session first
      await sessionCoordinator.startSession(
        sessionId: 'session_test_snooze',
        wardType: FocusWardType.morningAzkar,
      );

      await cubit.loadSettings();
      expect(cubit.state.hasActiveSession, isTrue);
      expect(cubit.state.remainingSnoozeCount, 2);

      // Snooze 1
      await cubit.snoozeActiveSession();
      expect(cubit.state.currentSnoozeCount, 1);
      expect(cubit.state.remainingSnoozeCount, 1);

      // Snooze 2
      await cubit.snoozeActiveSession();
      expect(cubit.state.currentSnoozeCount, 2);
      expect(cubit.state.remainingSnoozeCount, 0);

      // Snooze 3 (should fail/reject)
      await cubit.snoozeActiveSession();
      expect(cubit.state.currentSnoozeCount, 2);
      expect(cubit.state.errorMessage, contains('لا يمكن تأجيل الجلسة أكثر من مرتين'));
    });

    test('cancelActiveSession terminates session and clears active state', () async {
      await sessionCoordinator.startSession(
        sessionId: 'session_test_cancel',
        wardType: FocusWardType.eveningAzkar,
      );

      await cubit.loadSettings();
      expect(cubit.state.hasActiveSession, isTrue);

      await cubit.cancelActiveSession();

      expect(cubit.state.hasActiveSession, isFalse);
      expect(cubit.state.activeSession, isNull);
    });

    test('toggleMasterSwitch toggles master state and defaults to false', () async {
      await cubit.loadSettings();
      expect(cubit.state.isFocusModeMasterEnabled, isFalse);

      await cubit.toggleMasterSwitch(true);
      expect(cubit.state.isFocusModeMasterEnabled, isTrue);

      await cubit.toggleMasterSwitch(false);
      expect(cubit.state.isFocusModeMasterEnabled, isFalse);
    });
  });
}
