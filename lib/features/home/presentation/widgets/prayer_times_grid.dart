import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';
import 'package:intl/intl.dart';

class PrayerTimesGrid extends StatelessWidget {
  final int crossAxisCount; // عدد العواميد (2 للموبايل، 3 للتابلت)

  const PrayerTimesGrid({super.key, this.crossAxisCount = 2});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PrayerTimesCubit, PrayerTimesStates>(
      builder: (context, state) {
        if (state is! PrayerTimesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final prayers = _getPrayersList(state.prayerTimes);

        int rowCount = (prayers.length / crossAxisCount).ceil();

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
                        crossAxisCount == 1,
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

  // --- تصميم الكارت المرن (FittedBox هو السر) ---
  Widget _buildFlexCard(Map<String, dynamic> data, bool isWideLayout) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minHeight: 70 , minWidth: 100),
      decoration: BoxDecoration(
        color: AppColors.primaryBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondaryGold.withAlpha(100)),
      ),
      child: Flex(
        direction: isWideLayout ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: isWideLayout
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,

        children: [
          Expanded(
            flex: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              clipBehavior: Clip.antiAlias,
              child: Flex(
                direction: isWideLayout ? Axis.horizontal : Axis.vertical,
                spacing: isWideLayout ? 12.0 : 6.0,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(data['icon'], color: AppColors.secondaryGold, size: 28),
                  Text(
                    '${data['name']}',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            flex: isWideLayout ? 3 : 1,
            child: Text(
              data['time'] != null
                  ? DateFormat('hh:mm a', 'ar').format(data['time'])
                  : '--:--',
              style: GoogleFonts.cairo(
                color: AppColors.secondaryGold,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
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
