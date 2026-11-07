import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_tafseer_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_tafseer_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_tafseer_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Quran Tafseer Dependency Injection Registration Tests', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await init();
    });

    test('1. BaseQuranTafseerLocalDataSource is registered as LazySingleton', () {
      expect(sl.isRegistered<BaseQuranTafseerLocalDataSource>(), isTrue);
      final ds1 = sl<BaseQuranTafseerLocalDataSource>();
      final ds2 = sl<BaseQuranTafseerLocalDataSource>();
      expect(ds1, isA<QuranTafseerLocalDataSourceImpl>());
      expect(identical(ds1, ds2), isTrue, reason: 'Must be a singleton');
    });

    test('2. QuranTafseerRepository is registered as LazySingleton', () {
      expect(sl.isRegistered<QuranTafseerRepository>(), isTrue);
      final repo1 = sl<QuranTafseerRepository>();
      final repo2 = sl<QuranTafseerRepository>();
      expect(repo1, isA<QuranTafseerRepositoryImpl>());
      expect(identical(repo1, repo2), isTrue, reason: 'Must be a singleton');
    });

    test('3. GetQuranTafseerUseCase is registered as LazySingleton with repo injected', () {
      expect(sl.isRegistered<GetQuranTafseerUseCase>(), isTrue);
      final useCase1 = sl<GetQuranTafseerUseCase>();
      final useCase2 = sl<GetQuranTafseerUseCase>();
      expect(useCase1, isA<GetQuranTafseerUseCase>());
      expect(identical(useCase1, useCase2), isTrue, reason: 'Must be a singleton');
      expect(useCase1.repository, equals(sl<QuranTafseerRepository>()));
    });
  });
}

