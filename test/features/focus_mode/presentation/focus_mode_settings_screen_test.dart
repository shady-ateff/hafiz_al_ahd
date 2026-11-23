import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_schedule_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_app_exemption_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_scheduling_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_schedule_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_app_manager_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_schedule_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_recovery_manager.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_app_selection/focus_app_selection_cubit.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_permissions/focus_permissions_cubit.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_settings/focus_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/screens/focus_mode_settings_screen.dart';

class StubEnforcementPort implements FocusEnforcementPort {
  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async =>
      true;
  @override
  Future<bool> stopEnforcement() async => true;
  @override
  Future<bool> isEnforcing() async => false;
  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async =>
      FocusEnforcementStatus.stopped();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sl.reset();

    final scheduleRepo = FocusScheduleRepositoryImpl(
      localDataSource: FocusScheduleLocalDataSourceImpl.inMemory(),
    );
    final appExemptionRepo = FocusAppExemptionRepositoryImpl(
      localDataSource: FocusAppExemptionLocalDataSourceImpl.inMemory(),
    );
    final sessionRepo = FocusSessionRepositoryImpl(
      localDataSource: FocusSessionLocalDataSourceImpl.inMemory(),
    );
    final enforcementPort = StubEnforcementPort();

    final scheduleCoordinator = FocusScheduleCoordinator(
      repository: scheduleRepo,
      schedulingPort: InMemoryFocusSchedulingPort(),
    );

    final sessionCoordinator = FocusSessionCoordinator(
      adhkarPort: InMemoryAdhkarCompletionPort(),
      quranPort: InMemoryQuranReadingCompletionPort(),
      enforcementPort: enforcementPort,
      repository: sessionRepo,
    );

    final recoveryManager = FocusSessionRecoveryManager(
      repository: sessionRepo,
      enforcementPort: enforcementPort,
    );

    final appCoordinator = FocusAppManagerCoordinator(
      port: InMemoryFocusAppExemptionPort(),
      repository: appExemptionRepo,
    );

    sl.registerFactory<FocusPermissionsCubit>(() => FocusPermissionsCubit());
    sl.registerFactory<FocusSettingsCubit>(
      () => FocusSettingsCubit(
        scheduleCoordinator: scheduleCoordinator,
        sessionCoordinator: sessionCoordinator,
        scheduleRepository: scheduleRepo,
        appExemptionRepository: appExemptionRepo,
        recoveryManager: recoveryManager,
      ),
    );
    sl.registerFactory<FocusAppSelectionCubit>(
      () => FocusAppSelectionCubit(appCoordinator: appCoordinator),
    );
  });

  tearDown(() {
    sl.reset();
  });

  testWidgets('FocusModeSettingsScreen renders header, title, and cards', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: FocusModeSettingsScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('وضع التركيز'), findsOneWidget);
    expect(find.text('تفعيل وضع التركيز'), findsOneWidget);
    expect(find.text('حافظ على عهدك مع الله'), findsOneWidget);
    expect(find.text('أورادك اليومية المجدولة'), findsOneWidget);
    expect(find.text('أذكار الصباح'), findsOneWidget);
    expect(find.text('أذكار المساء'), findsOneWidget);
    expect(find.text('ورد القرآن الكريم'), findsOneWidget);
    expect(find.text('التطبيقات المستثناة أثناء الورد'), findsOneWidget);
  });

  testWidgets('Tapping on schedule time opens custom themed TimePicker', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: FocusModeSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Enable master switch so schedules are interactive
    final masterSwitch = find.byType(Switch).first;
    await tester.tap(masterSwitch);
    await tester.pumpAndSettle();

    final editTimeButton = find.byIcon(Icons.edit).first;
    await tester.ensureVisible(editTimeButton);
    await tester.pumpAndSettle();

    await tester.tap(editTimeButton);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('تحديد موعد الورد'), findsOneWidget);
    expect(find.text('تأكيد'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
  });
}
