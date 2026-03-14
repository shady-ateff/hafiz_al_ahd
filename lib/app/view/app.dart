import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hafiz_al_ahd/core/utils/app_theme.dart';
import 'package:hafiz_al_ahd/features/azkar/data/datasources/azkar_local_data_source.dart';
import 'package:hafiz_al_ahd/features/azkar/data/repositories/azkar_repository_impl.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/usecases/get_azkar_usecase.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_cubit.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/location_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/location_repository_impl.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/prayer_times_repo_impl.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/save_location_usecase.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/main/presentation/screens/main_screen.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/cancel_all_notfication_usecase.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/schedule_prayer_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

// 1. 👈 حولناها لـ StatefulWidget
class App extends StatefulWidget {
  final SharedPreferences sharedPreferences;
  const App({super.key, required this.sharedPreferences});

  @override
  State<App> createState() => _AppState();
}

// 2. 👈 ضفنا الـ Listeners بتاعة الويندوز والأيقونة
class _AppState extends State<App> with TrayListener, WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      trayManager.addListener(this);
      windowManager.addListener(this);
      _preventClose();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _preventClose() async {
    await windowManager.setPreventClose(true);
  }

  //  منع قفل البرنامج عند الضغط على X وإخفاؤه بدلاً من ذلك
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  //  إظهار الشاشة لما اليوزر يدوس على الأيقونة
  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  //  التفاعل مع القائمة الجانبية للأيقونة
  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_app') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.destroy();
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) {
            final localDataSource = PrayerTimesLocalDataSource();
            final prayerTimesRepo = PrayerTimesRepoImpl(localDataSource);
            final getPrayerTimesUseCase = GetPrayerTimesUseCase(
              prayerTimesRepo,
            );

            final locationDataSource = LocationLocalDataSourceImpl(
              // 👈 استخدمنا widget.sharedPreferences عشان إحنا جوه State
              sharedPreferences: widget.sharedPreferences,
            );
            final baseLocationRepo = LocationRepositoryImpl(
              localDataSource: locationDataSource,
            );
            final saveLocationUseCase = SaveLocationUseCase(baseLocationRepo);

            final getCachedLocationUseCase = GetCachedLocationUseCase(
              baseLocationRepo,
            );

            final cancelAllNotificationsUseCase = CancelAllNotificationsUseCase(
              NotificationRepositoryImpl(),
            );
            final schedulePrayerUseCase = SchedulePrayerUseCase(
              NotificationRepositoryImpl(),
            );

            return PrayerTimesCubit(
              initialState: PrayerTimesInitial(),
              getPrayerTimesUseCase: getPrayerTimesUseCase,
              saveLocationUseCase: saveLocationUseCase,
              getCachedLocationUseCase: getCachedLocationUseCase,
              cancelAllNotificationsUseCase: cancelAllNotificationsUseCase,
              schedulePrayerUseCase: schedulePrayerUseCase,
            )..fetchPrayerTimesByLocation();
          },
        ),
        BlocProvider(create: (context) => TimeCubit()),
        BlocProvider(
          create: (context) => AzkarCubit(
            getAzkarUseCase: GetAzkarUseCase(
              AzkarRepositoryImpl(localDataSource: AzkarLocalDataSourceImpl()),
            ),
          )..loadAzkar(),
        ),
      ],
      child: MaterialApp(
        title: 'Hafiz Al Ahd',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar', 'EG')],
        locale: const Locale('ar', 'EG'),
      ),
    );
  }
}
