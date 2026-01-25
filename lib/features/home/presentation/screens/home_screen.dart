import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_times_grid.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/time_date_section.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';

/// A screen that displays the current time and date in a visually appealing,
/// responsive layout. It adapts to both portrait and landscape orientations.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<PrayerTimesCubit>().fetchPrayerTimes(
      latitude: 30.0444,
      longitude: 31.2357,
      date: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use a deep, dark background for a luxurious feel.
      backgroundColor: AppColors.deepBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Determine if the screen is wide enough for a landscape layout.
            bool isLandscape = constraints.maxWidth > 600;

            /*_buildWatchLayout (لو العرض أقل من 300 مثلاً).

                _buildMobileLayout (لو العرض متوسط).

                _buildTabletDesktopLayout (لو العرض كبير جداً). */

            switch (constraints.maxWidth) {
              case (<= 300):
                return _buildWatchLayout();
              case (>= 301 && <= 800):
                return _buildMobileLayout();
              case (>= 801):
                return _buildTabletDesktopLayout(
                  maxHight: constraints.maxHeight,
                  maxWidth: constraints.maxWidth,
                );
              default:
                if (isLandscape) {
                  return _buildTabletDesktopLayout(
                    maxHight: constraints.maxHeight,
                    maxWidth: constraints.maxWidth,
                  );
                } else {
                  return _buildMobileLayout();
                }
            }
          },
        ),
      ),
    );
  }

  Widget _buildTabletDesktopLayout({
    required double maxHight,
    required double maxWidth,
  }) {
    double aspectRatio = maxWidth / maxHight;

    var calculatedCrossAxisCount = aspectRatio.floor() == 0
        ? 1
        : aspectRatio.floor();
 
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(flex: 4, child: TimeDateSection(isLandscape: true)),

            const SizedBox(width: 40),

            Expanded(
              flex: 3,
              child: PrayerTimesGrid(
                crossAxisCount: calculatedCrossAxisCount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return const Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20.0,
          ), // قللنا الحواف الجانبية شوية
          child: Column(
            children: [
              SizedBox(height: 30), // كانت 60، خليناها 30
              // قسم الساعة
              TimeDateSection(isLandscape: false),

              SizedBox(
                height: 30,
              ), // المسافة بين الساعة والصلوات كانت 60، كفاية 30
              // شبكة الصلوات
              PrayerTimesGrid(
                crossAxisCount: 2,
              ),

              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWatchLayout() {
    return Center(
      child: SingleChildScrollView(
        // Ensures the content doesn't overflow on vertically small screens.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              SizedBox(height: 60),
              TimeDateSection(isLandscape: false),
              const SizedBox(height: 60),
              PrayerTimesGrid(
                crossAxisCount: 1,
              ),
              SizedBox(height: 20),
              // Additional watch-specific UI components can be added here.
            ],
          ),
        ),
      ),
    );
  }
}
