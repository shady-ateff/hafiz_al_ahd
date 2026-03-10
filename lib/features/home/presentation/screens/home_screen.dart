import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/manual_location_dialog.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_times_grid.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/time_date_section.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

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
    context.read<PrayerTimesCubit>().fetchPrayerTimesByLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use a deep, dark background for a luxurious feel.
      // backgroundColor: AppColors.deepBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: AppColors.secondaryGold,
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<PrayerTimesCubit>().fetchPrayerTimesByLocation();
            },
          ),
        ],
        title: BlocConsumer<PrayerTimesCubit, PrayerTimesStates>(
          listener: (context, state) {
            // السحر كله هنا: مراقبة حالة اللوكيشن اليدوي
            if (state is PrayerTimesNeedsManualLocation) {
              showDialog(
                context: context,
                barrierDismissible:
                    false, // عشان اليوزر ميقفلش الديالوج من غير ما يختار حاجة
                builder: (context) => const ManualLocationDialog(),
              );
            }

            // ممكن تزود هنا حالة للـ Error لو حابب تظهر SnackBar
            if (state is PrayerTimesError) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.secondaryGold,
                ),
                Text(
                  state is PrayerTimesLoaded
                      ? state.city ?? "غير معروف"
                      : "جار التحميل...",
                  style: GoogleFonts.cairo(
                    color: AppColors.secondaryGold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Determine if the screen is wide enough for a landscape layout.
            bool isLandscape = constraints.maxWidth > 600;

            if (constraints.maxWidth <= 300) {
              return _buildWatchLayout();
            } else if (constraints.maxWidth >= 301 &&
                constraints.maxWidth <= 800) {
              return _buildMobileLayout();
            } else if (constraints.maxWidth >= 801) {
              return _buildTabletDesktopLayout(
                maxHeight: constraints.maxHeight,
                maxWidth: constraints.maxWidth,
              );
            } else {
              if (isLandscape) {
                return _buildTabletDesktopLayout(
                  maxHeight: constraints.maxHeight,
                  maxWidth: constraints.maxWidth,
                );
              } else {
                return SizedBox.shrink();
              }
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.read<PrayerTimesCubit>().testNotification();
        },
        backgroundColor: AppColors.secondaryGold,
        child: const Icon(Icons.refresh, color: AppColors.primaryBlack),
      )
    );
  }

  /// Builds the layout for Tablet and Desktop screens.
  Widget _buildTabletDesktopLayout({
    required double maxHeight,
    required double maxWidth,
  }) {
    double aspectRatio = maxWidth / maxHeight;

    var calculatedCrossAxisCount = aspectRatio.floor() == 0
        ? 2
        : aspectRatio.floor();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            const Expanded(
              flex: 4,
              child: TimeDateSection(isLandscape: false, isTabletDesktop: true),
            ),

            const SizedBox(width: 40),

            Expanded(
              flex: 3,
              child: PrayerTimesGrid(crossAxisCount: calculatedCrossAxisCount),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the layout for Mobile screens.
  Widget _buildMobileLayout() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          // SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
          Expanded(
            flex: 2,
            child: TimeDateSection(isLandscape: false, isMobile: true),
          ),

          Expanded(flex: 3, child: PrayerTimesGrid(crossAxisCount: 2)),
        ],
      ),
    );
  }

  /// Builds the layout for Watch/Small screens.
  Widget _buildWatchLayout() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
              SizedBox(
                height: 200,
                child: TimeDateSection(isLandscape: false, isWatch: true),
              ),
              const SizedBox(height: 60),
              PrayerTimesGrid(
                crossAxisCount: 1,
                isScrollable: true,
                forceVerticalCardLayout: false,
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
