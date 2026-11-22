import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_app_exemption_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/installed_app_info.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/app_exemption_policy.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_app_manager_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_app_selection/focus_app_selection_cubit.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/screens/focus_app_selection_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryFocusAppExemptionPort port;
  late FocusAppExemptionRepositoryImpl repository;
  late FocusAppManagerCoordinator coordinator;
  late FocusAppSelectionCubit cubit;

  setUp(() {
    port = InMemoryFocusAppExemptionPort();
    repository = FocusAppExemptionRepositoryImpl(
      localDataSource: FocusAppExemptionLocalDataSourceImpl.inMemory(),
    );
    coordinator = FocusAppManagerCoordinator(
      port: port,
      repository: repository,
      policy: const AppExemptionPolicy(
        ownPackageName: 'com.shadyatef.hafiz_alahd',
        systemCriticalPackages: {'com.android.dialer'},
      ),
    );

    port.apps = [
      const InstalledAppInfo(
        packageName: 'com.android.dialer',
        appName: 'الهاتف',
        isSystemApp: true,
      ),
      const InstalledAppInfo(
        packageName: 'com.google.android.calculator',
        appName: 'الآلة الحاسبة',
        isSystemApp: false,
      ),
    ];

    cubit = FocusAppSelectionCubit(appCoordinator: coordinator);
  });

  tearDown(() {
    cubit.close();
  });

  testWidgets('FocusAppSelectionScreen renders search, filter chips, and app list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<FocusAppSelectionCubit>.value(
          value: cubit,
          child: const FocusAppSelectionScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('التطبيقات المستثناة أثناء الورد'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('الكل (2)'), findsOneWidget);
    expect(find.text('السيادية (1)'), findsOneWidget);
    expect(find.text('الهاتف'), findsOneWidget);
    expect(find.text('الآلة الحاسبة'), findsOneWidget);
    expect(find.text('سيادي'), findsOneWidget);
  });
}
