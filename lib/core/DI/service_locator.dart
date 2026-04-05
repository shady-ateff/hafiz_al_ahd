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
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

// سميناه sl اختصاراً لـ Service Locator
final sl = GetIt.instance;

Future<void> init() async {
  // ---------------------------------------------------
  // 1. الحاجات الخارجية (External) زي الـ SharedPreferences
  // ---------------------------------------------------
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);

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
      pref: sl(), // جاب الـ SharedPreferences لوحده
    ),
  );
  sl.registerLazySingleton<BaseNotificationRepository>(
    () => NotificationRepositoryImpl(),
  );

  // 👈 ضيف الاتنين دول (أو حسب أساميهم عندك في المشروع)
  sl.registerLazySingleton<PrayerTimesRepo>(() => PrayerTimesRepoImpl(sl()));
  sl.registerLazySingleton<BaseLocationRepository>(
    () => LocationRepositoryImpl(localDataSource: sl()),
  );

  sl.registerLazySingleton(() => CancelAllNotificationsUseCase(sl()));
  sl.registerLazySingleton(() => SchedulePrayerUseCase(sl()));
  sl.registerLazySingleton(() => GetPrayerTimesUseCase(sl()));
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
}
