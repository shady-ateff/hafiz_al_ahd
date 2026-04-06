import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/manual_location_dialog.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_times_grid.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/time_date_section.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    context.read<PrayerTimesCubit>().fetchPrayerTimesByLocation();
  }

  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // الـ Scaffold بياخد الخلفية أوتوماتيك من الـ Theme
      appBar: AppBar(
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
            if (state is PrayerTimesNeedsManualLocation) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const ManualLocationDialog(),
              );
            }
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
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.secondaryGold,
                ),
                const SizedBox(width: 8),
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
                return const SizedBox.shrink();
              }
            }
          },
        ),
      ),
      floatingActionButton: kDebugMode
          ? BlocBuilder<PrayerTimesCubit, PrayerTimesStates>(
              builder: (context, state) {
                return FloatingActionButton(
                  onPressed: () {
                    context.read<PrayerTimesCubit>().testNotification(1);
                  },
                  child: const Icon(Icons.refresh),
                );
              },
            )
          : null,
    );
  }

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

  Widget _buildMobileLayout() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            flex: 2,
            child: TimeDateSection(isLandscape: false, isMobile: true),
          ),
          Expanded(flex: 3, child: PrayerTimesGrid(crossAxisCount: 2)),
        ],
      ),
    );
  }

  Widget _buildWatchLayout() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
              const SizedBox(
                height: 200,
                child: TimeDateSection(isLandscape: false, isWatch: true),
              ),
              const SizedBox(height: 60),
              const PrayerTimesGrid(
                crossAxisCount: 1,
                isScrollable: true,
                forceVerticalCardLayout: false,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
