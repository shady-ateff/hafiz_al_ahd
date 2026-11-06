import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/utils/app_theme.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/azkar/data/datasources/azkar_local_data_source.dart';
import 'package:hafiz_al_ahd/features/azkar/data/repositories/azkar_repository_impl.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/usecases/get_azkar_usecase.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_tracker_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/main/presentation/screens/main_screen.dart';
import 'package:hafiz_al_ahd/main.dart'; // For navigatorKey
import 'package:hafiz_al_ahd/features/onboarding/presentation/cubit/onboarding_cubit.dart';
import 'package:hafiz_al_ahd/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:hafiz_al_ahd/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart'; // 👈 استيراد المصحف
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_cubit.dart'; // 👈 استيراد اعدادات المصحف
import 'package:hafiz_al_ahd/features/splash/splash_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

// 1. 👈 حولناها لـ StatefulWidget
class App extends StatefulWidget {
  final String? initialRoute;
  const App({super.key, this.initialRoute});

  @override
  State<App> createState() => _AppState();
}

// 2. 👈 ضفنا الـ Listeners بتاعة الويندوز والأيقونة
class _AppState extends State<App> with TrayListener, WindowListener {
  late Future<bool> _onboardingFuture;

  /// True after the splash has been shown once in this process lifetime.
  /// Stays true even when app is backgrounded & resumed (same process).
  /// Resets to false only when the OS kills the process (cold start).
  static bool _splashShown = false;

  @override
  void initState() {
    super.initState();
    _onboardingFuture = OnboardingCubit.isOnboardingComplete();

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
          create: (context) =>
              sl<PrayerTimesCubit>()..fetchPrayerTimesByLocation(),
        ),
        BlocProvider(
          create: (context) => TimeCubit(
            onDayChanged: (newDate) {
              context.read<PrayerTimesCubit>().loadPrayerTimesFromCache();
            },
          ),
        ),
        BlocProvider(
          create: (context) => AzkarCubit(
            getAzkarUseCase: GetAzkarUseCase(
              AzkarRepositoryImpl(localDataSource: AzkarLocalDataSourceImpl()),
            ),
          )..loadAzkar(),
        ),
        BlocProvider(create: (context) => ThemeCubit()..loadSavedTheme()),
        BlocProvider(
          create: (context) => GamificationCubit(
            repository: GamificationRepositoryImpl(),
          )..init(),
        ),
        BlocProvider(create: (context) => AzkarTrackerCubit()),
        BlocProvider(create: (context) => sl<QuranCubit>()), // 👈 إضافة QuranCubit
        BlocProvider(create: (context) => sl<QuranSettingsCubit>()),
        BlocProvider(create: (context) => sl<QuranBookmarkCubit>()..loadBookmarks()), // 👈 إضافة اعدادات المصحف
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
            title: 'Hafiz Al Ahd',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeState.themeMode,
            home: FutureBuilder<bool>(
              future: _onboardingFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF121212),
                    body: Center(
                      child: AppLoader(),
                    ),
                  );
                }

                final isComplete = snapshot.data ?? false;
                final destination =
                    isComplete ? const MainScreen() : const OnboardingScreen();

                // Show splash only on the very first cold start of this process.
                // If _splashShown is already true, the app was merely resumed from
                // background — skip the splash entirely.
                if (!_splashShown) {
                  _splashShown = true;
                  return SplashScreen(nextScreen: destination);
                }

                return destination;
              },
            ),
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              );
            },
            debugShowCheckedModeBanner: true,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ar', 'EG')],
            locale: const Locale('ar', 'EG'),
          );
        },
      ),
    );
  }
}
