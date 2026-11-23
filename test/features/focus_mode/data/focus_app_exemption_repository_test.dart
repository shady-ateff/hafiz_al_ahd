import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_app_exemption_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_app_exemption_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/installed_app_info.dart';

void main() {
  late FocusAppExemptionLocalDataSourceImpl dataSource;
  late FocusAppExemptionRepositoryImpl repository;

  setUp(() {
    dataSource = FocusAppExemptionLocalDataSourceImpl.inMemory();
    repository = FocusAppExemptionRepositoryImpl(localDataSource: dataSource);
  });

  group('FocusAppExemptionRepository — Persistence Tests', () {
    test('saveExemptions and getAllSavedExemptions store and retrieve records', () async {
      final apps = [
        const InstalledAppInfo(
          packageName: 'com.calc',
          appName: 'آلة حاسبة',
          isExempt: true,
        ),
        const InstalledAppInfo(
          packageName: 'com.notes',
          appName: 'ملاحظات',
          isExempt: false,
        ),
      ];

      await repository.saveExemptions(apps);

      final retrieved = await repository.getAllSavedExemptions();
      expect(retrieved.length, 2);

      final calc = retrieved.firstWhere((a) => a.packageName == 'com.calc');
      expect(calc.isExempt, isTrue);

      final notes = retrieved.firstWhere((a) => a.packageName == 'com.notes');
      expect(notes.isExempt, isFalse);
    });

    test('getExemptPackageNames returns only packages marked as exempt', () async {
      await repository.setAppExemption(
        packageName: 'com.app1',
        isExempt: true,
        appName: 'تطبيق 1',
      );
      await repository.setAppExemption(
        packageName: 'com.app2',
        isExempt: false,
        appName: 'تطبيق 2',
      );
      await repository.setAppExemption(
        packageName: 'com.app3',
        isExempt: true,
        appName: 'تطبيق 3',
      );

      final exemptPackages = await repository.getExemptPackageNames();

      expect(exemptPackages.length, 2);
      expect(exemptPackages.contains('com.app1'), isTrue);
      expect(exemptPackages.contains('com.app3'), isTrue);
      expect(exemptPackages.contains('com.app2'), isFalse);
    });

    test('setAppExemption updates existing status in place', () async {
      await repository.setAppExemption(
        packageName: 'com.toggle',
        isExempt: false,
        appName: 'تبديل',
      );

      var exemptPackages = await repository.getExemptPackageNames();
      expect(exemptPackages.contains('com.toggle'), isFalse);

      await repository.setAppExemption(
        packageName: 'com.toggle',
        isExempt: true,
      );

      exemptPackages = await repository.getExemptPackageNames();
      expect(exemptPackages.contains('com.toggle'), isTrue);
    });

    test('clearExemptions removes all saved entries', () async {
      await repository.setAppExemption(
        packageName: 'com.app',
        isExempt: true,
      );

      expect((await repository.getAllSavedExemptions()).isNotEmpty, isTrue);

      await repository.clearExemptions();

      expect((await repository.getAllSavedExemptions()).isEmpty, isTrue);
    });
  });
}
