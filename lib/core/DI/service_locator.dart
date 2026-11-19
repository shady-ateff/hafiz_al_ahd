import 'package:get_it/get_it.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/location_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/location_repository_impl.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/prayer_times_repo_impl.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/base_location_repository.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/fetch_prayer_times_orchestrator_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/base_notification_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/check_if_scheduling_needed_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/check_location_change_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/show_sticky_notification_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/save_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/prayer_alarm_config_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/get_prayer_alarm_configs_use_case.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/save_prayer_alarm_config_use_case.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alert_transition_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/transition_coordinator.dart';
import 'package:http/http.dart' as http;
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/adhan_catalog_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/playable_audio_resolver_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/di/developer_service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';

// --- Quran Imports ---
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_repository.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_mapping_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_mapping_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_clipboard_service.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_share_service.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_bookmark_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_bookmark_repository.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_bookmark_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/add_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_bookmarks_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/toggle_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/is_ayah_bookmarked_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/remove_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_tafseer_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_tafseer_repository.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_tafseer_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_tafseer_cubit.dart';

// --- Quran Audio Feature Imports (QA.1, QA.2, QA.3) ---
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_handler.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_service_initializer.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_timing_validator.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/quran_audio_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_audio_download_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/repositories/base_quran_audio_repository.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/delete_download_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_downloaded_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_reciters_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/get_surah_audio_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/usecases/save_playback_position_use_case.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_cubit.dart';

// سميناه sl اختصاراً لـ Service Locator
final sl = GetIt.instance;

Future<void> init() async {
  // ---------------------------------------------------
  // 1. الحاجات الخارجية (External) زي الـ SharedPreferences
  // ---------------------------------------------------
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton<http.Client>(() => http.Client());

  // ---------------------------------------------------
  // 2. الـ UseCases (هنسجل القدام والجداد)
  // ---------------------------------------------------
  // ---------------------------------------------------
  // 1.2 الـ Data Sources (الطبقة السفلية)
  // ---------------------------------------------------

  // 👈 ضيف الـ Local Data Source اللي الإيرور بيسأل عليه
  sl.registerLazySingleton<PrayerTimesLocalDataSource>(
    () => PrayerTimesLocalDataSource(), // لو بياخد SharedPreferences
  );

  // ولو عندك Location Data Sources ضيفها
  sl.registerLazySingleton<BaseLocationLocalDataSource>(
    () => LocationLocalDataSourceImpl(sharedPreferences: sl()),
  );
  // بص السحر: هنا الـ UseCase دي محتاجة SharedPreferences
  // بدل ما نبعتهالها، بنكتب sl() وهو هيدور في المخزن ويجيبها لوحده! 🪄
  sl.registerLazySingleton(() => CheckIfSchedulingNeededUseCase(pref: sl()));

  sl.registerLazySingleton(
    () => CheckLocationChangeUseCase(getCachedLocationUseCase: sl()),
  );

  sl.registerLazySingleton(
    () => ScheduleWeeklyPrayersUseCase(
      getPrayerTimesUseCase: sl(),
      cancelAllNotificationsUseCase: sl(),
      schedulePrayerUseCase: sl(),
      getIqamaDelaysUseCase: sl(),
      notificationRepository: sl(),
      pref: sl(), // جاب الـ SharedPreferences لوحده
      prayerAlarmConfigRepository: sl(),
      playableAudioResolver: sl(),
    ),
  );
  sl.registerLazySingleton<BaseNotificationRepository>(
    () => NotificationRepositoryImpl(),
  );

  // Audio Storage Concurrency & Reference Lock
  sl.registerLazySingleton<BaseAudioStorageLock>(
    () => AudioStorageLock(),
  );

  // Prayer Alarm Config
  sl.registerLazySingleton<BasePrayerAlarmConfigLocalDataSource>(
    () => PrayerAlarmConfigLocalDataSourceImpl(prefs: sl()),
  );
  sl.registerLazySingleton<BasePrayerAlarmConfigRepository>(
    () => PrayerAlarmConfigRepositoryImpl(
      localDataSource: sl(),
      audioStorageLock: sl(),
      storageService: sl(),
    ),
  );
  sl.registerLazySingleton(() => GetPrayerAlarmConfigsUseCase(sl()));
  sl.registerLazySingleton(() => SavePrayerAlarmConfigUseCase(sl()));

  // Prayer Alert Transitions & Custom Audio
  sl.registerLazySingleton<BasePrayerAlertTransitionLocalDataSource>(
    () => PrayerAlertTransitionLocalDataSourceImpl(prefs: sl()),
  );
  sl.registerLazySingleton(() => CustomAudioStorageService());

  // Remote Adhan Audio Catalog (Phase 2)
  sl.registerLazySingleton<BaseAdhanCatalogRemoteDataSource>(
    () => AdhanCatalogRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<BaseAdhanCatalogLocalDataSource>(
    () => AdhanCatalogLocalDataSourceImpl(prefs: sl()),
  );
  sl.registerLazySingleton<BaseAdhanCatalogRepository>(
    () => AdhanCatalogRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<BaseAudioDownloadService>(
    () => AudioDownloadServiceImpl(
      client: sl(),
      storageService: sl(),
      quotaAdmissionGuard: (requiredBytes) =>
          sl<BaseAdhanStorageManagerService>().checkQuota(requiredBytes: requiredBytes),
    ),
  );
  sl.registerLazySingleton<BasePlayableAudioResolver>(
    () => PlayableAudioResolverImpl(
      storageService: sl(),
    ),
  );
  sl.registerLazySingleton<BaseAdhanStorageManagerService>(
    () => AdhanStorageManagerServiceImpl(
      storageService: sl(),
      prayerConfigDataSource: sl(),
      downloadService: sl(),
      audioStorageLock: sl(),
      prefs: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => TransitionCoordinator(
      configRepository: sl(),
      transitionDataSource: sl(),
      cancelAlarmSafely: (id, {expectedScheduledTime, expectedAssetAudioPath}) =>
          sl<BaseNotificationRepository>().cancelAlarmSafely(
        id,
        expectedScheduledTime: expectedScheduledTime,
        expectedAssetAudioPath: expectedAssetAudioPath,
      ),
      stopActiveAlarm: (id) => Alarm.stop(id),
      cancelNotificationSafely: (id) =>
          sl<BaseNotificationRepository>().cancelNotificationSafely(id),
      scheduleAlarm: (prayerId, dt, audio, vol, vib) =>
          sl<BaseNotificationRepository>().scheduleAdhanAlarm(
        id: (dt.year % 100 * 1000000) + (dt.month * 10000) + (dt.day * 100) + (prayerId.index * 10) + 0,
        title: 'حان الآن موعد صلاة ${prayerId.arabicName}',
        body: prayerId == PrayerId.fajr ? 'الصلاة خير من النوم' : 'حي على الصلاة، حي على الفلاح',
        scheduledTime: dt,
        assetAudioPath: audio is BuiltInAudioSource
            ? audio.resolveAssetPath(isFajr: prayerId == PrayerId.fajr)
            : (audio as CustomAudioSource).localRelativePath,
        volume: vol,
        enableVibration: vib,
      ),
      scheduleNotification: (prayerId, dt) =>
          sl<BaseNotificationRepository>().schedulePrayerNotification(
        id: (dt.year % 100 * 1000000) + (dt.month * 10000) + (dt.day * 100) + (prayerId.index * 10) + 1,
        title: 'حان الآن موعد صلاة ${prayerId.arabicName}',
        body: prayerId == PrayerId.fajr ? 'الصلاة خير من النوم' : 'حي على الصلاة، حي على الفلاح',
        scheduledTime: dt,
      ),
      getPrayerTimesForHorizon: (prayerId) async {
        final getPrayerTimes = sl<GetPrayerTimesUseCase>();
        final getCachedLocation = sl<GetCachedLocationUseCase>();
        final loc = await getCachedLocation();
        final lat = loc.fold((_) => 30.0444, (r) => r.latitude);
        final lng = loc.fold((_) => 31.2357, (r) => r.longitude);
        final now = DateTime.now();
        final List<DateTime> times = [];
        for (int i = 0; i < 5; i++) {
          final date = DateTime(now.year, now.month, now.day + i);
          final res = await getPrayerTimes(latitude: lat, longitude: lng, date: date);
          res.fold((_) {}, (entity) {
            DateTime? t;
            switch (prayerId) {
              case PrayerId.fajr: t = entity.fajr; break;
              case PrayerId.dhuhr: t = entity.dhuhr; break;
              case PrayerId.asr: t = entity.asr; break;
              case PrayerId.maghrib: t = entity.maghrib; break;
              case PrayerId.isha: t = entity.isha; break;
            }
            if (t != null) times.add(t);
          });
        }
        return times;
      },
    ),
  );

  sl.registerFactory(
    () => PrayerAlarmSettingsCubit(
      configRepository: sl(),
      transitionCoordinator: sl(),
      transitionDataSource: sl(),
      prefs: sl(),
      audioStorageLock: sl(),
      storageService: sl(),
    ),
  );
  sl.registerFactory(
    () => AdhanCatalogCubit(
      catalogRepository: sl(),
      downloadService: sl(),
      playableAudioResolver: sl(),
      storageManagerService: sl(),
    ),
  );

  // 👈 ضيف الاتنين دول (أو حسب أساميهم عندك في المشروع)
  sl.registerLazySingleton<PrayerTimesRepo>(() => PrayerTimesRepoImpl(sl()));
  sl.registerLazySingleton<BaseLocationRepository>(
    () => LocationRepositoryImpl(localDataSource: sl()),
  );

  sl.registerLazySingleton(() => CancelAllNotificationsUseCase(sl()));
  sl.registerLazySingleton(() => SchedulePrayerUseCase(sl()));
  sl.registerLazySingleton(() => GetPrayerTimesUseCase(sl(), pref: sl()));
  sl.registerLazySingleton(() => SaveLocationUseCase(sl()));
  sl.registerLazySingleton(() => GetCachedLocationUseCase(sl()));
  sl.registerLazySingleton(() => ShowStickyNotificationUseCase(sl()));
  sl.registerLazySingleton(() => GetIqamaDelaysUseCase());
  sl.registerLazySingleton(() => SaveIqamaDelaysUseCase());
  sl.registerLazySingleton(
    () => FetchPrayerTimesOrchestrator(
      getPrayerTimesUseCase: sl(),
      saveLocationUseCase: sl(),
    ),
  );
  // ---------------------------------------------------
  // 3. الـ Cubits / Blocs
  // ---------------------------------------------------
  sl.registerFactory(
    () => PrayerTimesCubit(
      fetchOrchestrator: sl(),
      getPrayerTimesUseCase: sl(),
      saveLocationUseCase: sl(),
      getCachedLocationUseCase: sl(),
      showStickyNotificationUseCase: sl(),
      checkLocationChangeUseCase: sl(),
      checkIfSchedulingNeededUseCase: sl(),
      scheduleWeeklyPrayersUseCase: sl(),
      schedulePrayerUseCase: sl(),
      cancelAllNotificationsUseCase: sl(),
    ),
  );
  // ---------------------------------------------------
  // 4. Quran Feature
  // ---------------------------------------------------
  sl.registerLazySingleton<BaseQuranLocalDataSource>(
    () => QuranLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<BaseQuranRepository>(
    () => QuranRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<BaseQuranMappingLocalDataSource>(
    () => QuranMappingLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<BaseQuranMappingRepository>(
    () => QuranMappingRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton(() => GetQuranPageUseCase(sl()));
  sl.registerFactory(
    () => QuranCubit(getQuranPageUseCase: sl(), mappingRepository: sl()),
  );
  sl.registerFactory(() => QuranSettingsCubit(sharedPreferences: sl()));
  sl.registerLazySingleton<QuranClipboardService>(
    () => const QuranClipboardService(),
  );
  sl.registerLazySingleton<QuranShareService>(() => QuranShareService());

  // Quran Bookmarks (Phase 2.6.3.4)
  sl.registerLazySingleton<BaseQuranBookmarkLocalDataSource>(
    () => QuranBookmarkLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<QuranBookmarkRepository>(
    () => QuranBookmarkRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton(() => GetQuranBookmarksUseCase(sl()));
  sl.registerLazySingleton(() => AddQuranBookmarkUseCase(sl()));
  sl.registerLazySingleton(() => ToggleQuranBookmarkUseCase(sl()));
  sl.registerLazySingleton(() => IsAyahBookmarkedUseCase(sl()));
  sl.registerLazySingleton(() => RemoveQuranBookmarkUseCase(sl()));
  sl.registerFactory(
    () => QuranBookmarkCubit(
      getBookmarksUseCase: sl(),
      toggleBookmarkUseCase: sl(),
      removeBookmarkUseCase: sl(),
      addBookmarkUseCase: sl(),
    ),
  );

  // Quran Tafseer (Phase 2.6.3.5)
  sl.registerLazySingleton<BaseQuranTafseerLocalDataSource>(
    () => QuranTafseerLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<QuranTafseerRepository>(
    () => QuranTafseerRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton(() => GetQuranTafseerUseCase(sl()));
  sl.registerFactory(() => QuranTafseerCubit(getQuranTafseerUseCase: sl()));

  // ---------------------------------------------------
  // 4.1. Quran Audio Feature (Phase QA.1)
  // ---------------------------------------------------
  sl.registerLazySingleton<BaseQuranAudioDatabase>(
    () => QuranAudioDatabase(),
  );
  sl.registerLazySingleton<QuranAudioStorageService>(
    () => const QuranAudioStorageService(),
  );
  sl.registerLazySingleton<BaseQuranAudioLocalDataSource>(
    () => QuranAudioLocalDataSourceImpl(
      database: sl(),
      prefs: sl(),
    ),
  );
  sl.registerLazySingleton<BaseQuranAudioRemoteDataSource>(
    () => QuranAudioRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<BaseQuranAudioRepository>(
    () => QuranAudioRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<BaseAudioDownloadRepository>(
    () => AudioDownloadRepositoryImpl(
      localDataSource: sl(),
      storageService: sl(),
    ),
  );
  sl.registerLazySingleton<BaseQuranAudioDownloadService>(
    () => QuranAudioDownloadService(
      localDataSource: sl(),
      storageService: sl(),
    ),
  );
  sl.registerLazySingleton<AyahTimingValidator>(
    () => const AyahTimingValidator(),
  );
  sl.registerFactory<AyahTrackingEngine>(
    () => AyahTrackingEngine(),
  );
  sl.registerLazySingleton(() => GetRecitersUseCase(sl()));
  sl.registerLazySingleton(() => GetSurahAudioUseCase(sl()));
  sl.registerLazySingleton(() => SavePlaybackPositionUseCase(sl()));
  sl.registerLazySingleton(() => GetPlaybackPositionUseCase(sl()));
  sl.registerLazySingleton(() => GetDownloadedAudioUseCase(sl()));
  sl.registerLazySingleton(() => DeleteDownloadUseCase(sl()));

  // 4.2. Audio Engine, Background Handler & Presentation (Phase QA.2 & QA.3)
  final audioPlayer = QuranAudioPlayerImpl();
  sl.registerSingleton<QuranAudioPlayer>(audioPlayer);

  // AudioService is initialized during di.init() before runApp
  final audioHandler = await QuranAudioServiceInitializer.initialize(
    player: audioPlayer,
    getSurahAudioUseCase: sl(),
    savePlaybackPositionUseCase: sl(),
  );
  sl.registerSingleton<QuranAudioHandler>(audioHandler);

  sl.registerFactory<QuranAudioCubit>(
    () => QuranAudioCubit(
      getRecitersUseCase: sl(),
      getSurahAudioUseCase: sl(),
      audioHandler: sl(),
      trackingEngine: sl(),
      savePlaybackPositionUseCase: sl(),
      getPlaybackPositionUseCase: sl(),
      downloadService: sl(),
      downloadRepository: sl(),
    ),
  );

  // ---------------------------------------------------
  // 5. Developer Tools (Phase 4 - Debug Mode Only)
  // ---------------------------------------------------
  if (isCatalogDeveloperToolsActive) {
    registerDeveloperServices(sl);
  }
}
