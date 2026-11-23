import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_focus_app_exemption_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/installed_app_info.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/app_exemption_policy.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_app_manager_coordinator.dart';

void main() {
  late InMemoryFocusAppExemptionPort port;
  late FocusAppExemptionRepositoryImpl repository;
  late FocusAppManagerCoordinator coordinator;

  setUp(() {
    port = InMemoryFocusAppExemptionPort();
    final dataSource = FocusAppExemptionLocalDataSourceImpl.inMemory();
    repository = FocusAppExemptionRepositoryImpl(localDataSource: dataSource);
    coordinator = FocusAppManagerCoordinator(
      port: port,
      repository: repository,
      policy: const AppExemptionPolicy(
        ownPackageName: 'com.shadyatef.hafiz_alahd',
        systemCriticalPackages: {'com.android.dialer', 'com.android.launcher'},
      ),
    );
  });

  group('FocusAppManagerCoordinator — App Management & Exemption Sync', () {
    test('getAppsWithExemptions merges installed apps with persisted state and flags criticals', () async {
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

      // User had previously marked calculator as exempt in DB
      await repository.setAppExemption(
        packageName: 'com.google.android.calculator',
        isExempt: true,
        appName: 'الآلة الحاسبة',
      );

      final apps = await coordinator.getAppsWithExemptions();

      expect(apps.length, 3);

      final dialer = apps.firstWhere((a) => a.packageName == 'com.android.dialer');
      expect(dialer.isSystemCritical, isTrue);
      expect(dialer.isExempt, isTrue); // System critical is always exempt

      final calc = apps.firstWhere((a) => a.packageName == 'com.google.android.calculator');
      expect(calc.isSystemCritical, isFalse);
      expect(calc.isExempt, isTrue); // From persisted DB

      final fb = apps.firstWhere((a) => a.packageName == 'com.facebook.katana');
      expect(fb.isSystemCritical, isFalse);
      expect(fb.isExempt, isFalse); // Default not exempt
    });

    test('toggleAppExemption updates repository and syncs with native port', () async {
      port.apps = [
        const InstalledAppInfo(
          packageName: 'com.google.android.calculator',
          appName: 'الآلة الحاسبة',
        ),
      ];

      expect(port.syncedExemptions.contains('com.google.android.calculator'), isFalse);

      await coordinator.toggleAppExemption('com.google.android.calculator', true,
          appName: 'الآلة الحاسبة');

      final exemptNames = await repository.getExemptPackageNames();
      expect(exemptNames.contains('com.google.android.calculator'), isTrue);

      expect(port.syncedExemptions.contains('com.google.android.calculator'), isTrue);
      // Invariants must also be present in native sync payload
      expect(port.syncedExemptions.contains('com.shadyatef.hafiz_alahd'), isTrue);
    });

    test('toggleAppExemption throws UnsupportedError for system critical app', () async {
      expect(
        () => coordinator.toggleAppExemption('com.android.dialer', false),
        throwsUnsupportedError,
      );
    });

    test('syncAllExemptionsToNative sends combined set of user exemptions and criticals', () async {
      await repository.setAppExemption(
        packageName: 'com.example.notes',
        isExempt: true,
        appName: 'الملاحظات',
      );

      final success = await coordinator.syncAllExemptionsToNative();

      expect(success, isTrue);
      expect(port.syncedExemptions.contains('com.example.notes'), isTrue);
      expect(port.syncedExemptions.contains('com.android.dialer'), isTrue);
      expect(port.syncedExemptions.contains('com.shadyatef.hafiz_alahd'), isTrue);
      expect(port.syncedExemptions.contains('com.android.incallui'), isTrue);
    });
  });
}
