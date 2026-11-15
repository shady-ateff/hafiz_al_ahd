import 'package:get_it/get_it.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/data/services/catalog_draft_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/data/services/local_audio_hasher_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/local_audio_hasher_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';

/// Registers developer-only services into GetIt.
///
/// This function is ONLY invoked when [isCatalogDeveloperToolsActive] evaluates to true.
/// In Release builds, whole-program optimization treeshakes this file and its dependencies.
void registerDeveloperServices(GetIt sl) {
  if (!sl.isRegistered<AdhanCatalogValidator>()) {
    sl.registerLazySingleton<AdhanCatalogValidator>(
      () => const AdhanCatalogValidator(),
    );
  }

  if (!sl.isRegistered<LocalAudioHasherService>()) {
    sl.registerLazySingleton<LocalAudioHasherService>(
      () => LocalAudioHasherServiceImpl(),
    );
  }

  if (!sl.isRegistered<CatalogDraftManagerService>()) {
    sl.registerLazySingleton<CatalogDraftManagerService>(
      () => CatalogDraftManagerServiceImpl(
        catalogRepository: sl<BaseAdhanCatalogRepository>(),
        validator: sl<AdhanCatalogValidator>(),
      ),
    );
  }

  if (!sl.isRegistered<AdhanCatalogDeveloperCubit>()) {
    sl.registerFactory<AdhanCatalogDeveloperCubit>(
      () => AdhanCatalogDeveloperCubit(
        catalogRepository: sl<BaseAdhanCatalogRepository>(),
        draftManager: sl<CatalogDraftManagerService>(),
        validator: sl<AdhanCatalogValidator>(),
      ),
    );
  }
}
