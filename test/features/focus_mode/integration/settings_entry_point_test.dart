import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
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
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/base_location_repository.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/save_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StubLocationRepo implements BaseLocationRepository {
  @override
  Future<Either<Failure, LocationEntity>> getCachedLocation() async {
    return Right(LocationEntity(
      city: 'Cairo',
      country: 'Egypt',
      latitude: 30.0444,
      longitude: 31.2357,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StubEnforcementPort implements FocusEnforcementPort {
  @override
  Future<bool> startEnforcement({required String sessionId, required String wardTitle}) async => true;
  @override
  Future<bool> stopEnforcement() async => true;
  @override
  Future<bool> isEnforcing() async => false;
  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async => FocusEnforcementStatus.stopped();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    sl.reset();

    const MethodChannel pocChannel =
        MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');
    const MethodChannel permHandlerChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pocChannel, (call) async {
      if (call.method == 'checkPermissions') {
        return {
          'hasUsageAccess': false,
          'hasOverlayPermission': false,
          'canScheduleExactAlarms': true,
        };
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permHandlerChannel, (call) async => 1);

    SharedPreferences.setMockInitialValues({
      'isIqamaEnabled': true,
      'dst_offset_minutes': 0,
      'adhan_volume': 1.0,
      'isAdhanVibrationEnabled': true,
      'isAzkarReminderEnabled': true,
      'calculation_method': 'auto',
      'madhab': 'shafi',
      'adhanStyle': 'alarm',
    });
    prefs = await SharedPreferences.getInstance();

    sl.registerSingleton<SharedPreferences>(prefs);
    sl.registerSingleton<GetIqamaDelaysUseCase>(GetIqamaDelaysUseCase());
    sl.registerSingleton<SaveIqamaDelaysUseCase>(SaveIqamaDelaysUseCase());
    sl.registerSingleton<GetCachedLocationUseCase>(
      GetCachedLocationUseCase(StubLocationRepo()),
    );

    // Register Focus Mode dependencies
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

  testWidgets('SettingsScreen displays Focus Mode card and navigates to FocusModeSettingsScreen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Focus Mode card is present in Settings
    final focusCardFinder = find.text('وضع التركيز (حماية الأوراد)');
    expect(focusCardFinder, findsOneWidget);
    expect(find.text('حماية أوقات الأذكار والقرآن بحجب المشتتات'), findsOneWidget);

    // Tap on the card
    await tester.tap(focusCardFinder);
    await tester.pumpAndSettle();

    // Verify navigation landed on FocusModeSettingsScreen
    expect(find.text('حافظ على عهدك مع الله'), findsOneWidget);
    expect(find.text('أورادك اليومية المجدولة'), findsOneWidget);
  });

  testWidgets('SettingsScreen displays App Permissions card and navigates to AppPermissionsScreen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify App Permissions card is present in Settings
    final permissionsCardFinder = find.text('فحص صلاحيات التطبيق');
    expect(permissionsCardFinder, findsOneWidget);

    // Scroll to it and tap
    await tester.ensureVisible(permissionsCardFinder);
    await tester.tap(permissionsCardFinder);
    await tester.pumpAndSettle();

    // Verify navigation landed on AppPermissionsScreen
    expect(find.text('فحص صلاحيات التطبيق'), findsWidgets);
    expect(find.text('صلاحيات الأذان ومواقيت الصلاة الأساسية'), findsOneWidget);
  });
}
