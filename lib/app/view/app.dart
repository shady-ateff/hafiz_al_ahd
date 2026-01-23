import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hafiz_al_ahd/core/utils/app_theme.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/data/repositories/prayer_times_repo_impl.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hafiz Al Ahd',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) {
            final localDataSource = PrayerTimesLocalDataSource();
            final prayerTimesRepo = PrayerTimesRepoImpl(localDataSource);
            final getPrayerTimesUseCase = GetPrayerTimesUseCase(prayerTimesRepo) ; // Obtain the use case instance
            return PrayerTimesCubit(getPrayerTimesUseCase: getPrayerTimesUseCase, initialState: PrayerTimesInitial());
          }),
          BlocProvider(create: (context) => TimeCubit()),
        ],
        child: HomeScreen(),
      ),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        // Add localization delegates here if needed
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'EG')],
      locale: const Locale('ar', 'EG'),
    );
  }
}
