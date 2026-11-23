import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_app_exemption_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/installed_app_info.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/app_exemption_policy.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_app_manager_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_app_selection/focus_app_selection_cubit.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/cubits/focus_app_selection/focus_app_selection_state.dart';

void main() {
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
        systemCriticalPackages: {'com.android.dialer', 'com.android.launcher'},
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
      const InstalledAppInfo(
        packageName: 'com.facebook.katana',
        appName: 'فيسبوك',
        isSystemApp: false,
      ),
    ];

    cubit = FocusAppSelectionCubit(appCoordinator: coordinator);
  });

  tearDown(() {
    cubit.close();
  });

  group('FocusAppSelectionCubit Tests', () {
    test('loadApps loads apps and identifies system criticals', () async {
      await cubit.loadApps();

      expect(cubit.state.allApps.length, 3);
      expect(cubit.state.displayedApps.length, 3);
      expect(cubit.state.criticalCount, 1); // Phone dialer
      expect(cubit.state.isLoading, isFalse);
    });

    test('search filters apps by Arabic name or package substring', () async {
      await cubit.loadApps();

      cubit.search('حاسبة');
      expect(cubit.state.displayedApps.length, 1);
      expect(cubit.state.displayedApps.first.packageName,
          'com.google.android.calculator');

      cubit.search('facebook');
      expect(cubit.state.displayedApps.length, 1);
      expect(cubit.state.displayedApps.first.packageName,
          'com.facebook.katana');

      cubit.search('');
      expect(cubit.state.displayedApps.length, 3);
    });

    test('filterByTab filters by all, exempt, and critical tabs', () async {
      await cubit.loadApps();

      // Initially only system critical dialer is exempt
      cubit.filterByTab(AppFilterTab.critical);
      expect(cubit.state.displayedApps.length, 1);
      expect(cubit.state.displayedApps.first.packageName, 'com.android.dialer');

      cubit.filterByTab(AppFilterTab.exempt);
      expect(cubit.state.displayedApps.length, 1);

      cubit.filterByTab(AppFilterTab.all);
      expect(cubit.state.displayedApps.length, 3);
    });

    test('toggleExemption modifies non-critical app and preserves criticals', () async {
      await cubit.loadApps();

      await cubit.toggleExemption('com.google.android.calculator', true);

      final calc = cubit.state.allApps
          .firstWhere((a) => a.packageName == 'com.google.android.calculator');
      expect(calc.isExempt, isTrue);

      // Attempting to toggle system critical dialer should be a no-op
      await cubit.toggleExemption('com.android.dialer', false);
      final dialer = cubit.state.allApps
          .firstWhere((a) => a.packageName == 'com.android.dialer');
      expect(dialer.isExempt, isTrue); // Invariant maintained
    });
  });
}
