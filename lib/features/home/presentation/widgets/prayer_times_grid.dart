import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_card_widget.dart';
import 'package:intl/intl.dart';

class PrayerTimesGrid extends StatelessWidget {
  /// The number of columns in the grid.
  /// Typically 2 for mobile and 3 for tablet/desktop.
  final int crossAxisCount;

  /// Whether the grid should be scrollable.
  final bool isScrollable;

  /// Whether to force specific vertical card layout.
  final bool forceVerticalCardLayout;

  const PrayerTimesGrid({
    super.key,
    this.crossAxisCount = 2,
    this.isScrollable = false,
    this.forceVerticalCardLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PrayerTimesCubit, PrayerTimesStates>(
      builder: (context, state) {
        if (state is! PrayerTimesLoaded) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.secondaryGold),
          );
        }

        final prayers = _getPrayersList(state.prayerTimes);
        final nextPrayer = state.prayerTimes.getNextPrayer(DateTime.now());

        int rowCount = (prayers.length / crossAxisCount).ceil();

        if (isScrollable) {
          return Column(
            children: List.generate(rowCount, (rowIndex) {
              return Row(
                children: List.generate(crossAxisCount, (colIndex) {
                  int itemIndex = (rowIndex * crossAxisCount) + colIndex;

                  if (itemIndex < prayers.length) {
                    return Expanded(
                      child: _buildFlexCard(
                        prayers[itemIndex],
                        crossAxisCount == 1,
                        nextPrayer.name,
                      ),
                    );
                  } else {
                    return const Spacer();
                  }
                }),
              );
            }),
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(rowCount, (rowIndex) {
            return Expanded(
              child: Row(
                children: List.generate(crossAxisCount, (colIndex) {
                  int itemIndex = (rowIndex * crossAxisCount) + colIndex;

                  if (itemIndex < prayers.length) {
                    return Expanded(
                      child: _buildFlexCard(
                        prayers[itemIndex],
                        forceVerticalCardLayout
                            ? !forceVerticalCardLayout
                            : crossAxisCount == 1,
                        nextPrayer.name,
                      ),
                    );
                  } else {
                    return const Spacer();
                  }
                }),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildFlexCard(
    Map<String, dynamic> data,
    bool isWideLayout,
    String? nextPrayerName,
  ) {
    return PrayerCard(
      name: data['name'],
      time: data['time'],
      icon: data['icon'],
      remaining: data['remaining'],
      isWideLayout: isWideLayout,
      isNextPrayer: nextPrayerName == data['name'],
    );
  }

  List<Map<String, dynamic>> _getPrayersList(PrayerTimesEntity times) {
    return [
      {'name': 'الفجر', 'time': times.fajr, 'icon': Icons.nightlight_round},
      {
        'name': 'الشروق',
        'time': times.sunrise,
        'icon': Icons.wb_sunny_outlined,
      },
      {'name': 'الظهر', 'time': times.dhuhr, 'icon': Icons.wb_sunny},
      {'name': 'العصر', 'time': times.asr, 'icon': Icons.wb_cloudy_outlined},
      {'name': 'المغرب', 'time': times.maghrib, 'icon': Icons.wb_twilight},
      {'name': 'العشاء', 'time': times.isha, 'icon': Icons.nights_stay},
    ];
  }
}
