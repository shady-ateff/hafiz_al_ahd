import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hafiz_al_ahd/core/utils/app_theme.dart';
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
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class App extends StatelessWidget {
  final SharedPreferences sharedPreferences;
  const App({super.key, required this.sharedPreferences});

  @override
  @override
  Widget build(BuildContext context) {
    // 1. 👈 الاختلاف الأول: الـ MultiBlocProvider بقى هو الأب بره خالص
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
              sharedPreferences: sharedPreferences,
            );
            final baseLocationRepo = LocationRepositoryImpl(
              localDataSource: locationDataSource,
            );
            final saveLocationUseCase = SaveLocationUseCase(baseLocationRepo);
            final getCachedLocationUseCase = GetCachedLocationUseCase(
              baseLocationRepo,
            );

            return PrayerTimesCubit(
              initialState: PrayerTimesInitial(),
              getPrayerTimesUseCase: getPrayerTimesUseCase,
              saveLocationUseCase: saveLocationUseCase,
              getCachedLocationUseCase: getCachedLocationUseCase,
            )..fetchPrayerTimesByLocation();
          },
        ),
        BlocProvider(create: (context) => TimeCubit()),
      ],
      // 2. 👈 الاختلاف التاني: الـ MaterialApp بقى هو الـ child
      child: MaterialApp(
        title: 'Hafiz Al Ahd',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,

        // 3. 👈 الاختلاف التالت: الـ home بقت الشاشة على طول
        home: const HomeScreen(),

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
