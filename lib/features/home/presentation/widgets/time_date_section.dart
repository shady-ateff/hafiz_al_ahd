import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';

class TimeDateSection extends StatelessWidget {
  const TimeDateSection({
    super.key,
    required this.isLandscape,
    this.isTabletDesktop = false,
    this.isMobile = false,
    this.isWatch = false,
  });

  final bool isLandscape;
  final bool isTabletDesktop;
  final bool isMobile;
  final bool isWatch;

  @override
  Widget build(BuildContext context) {
    // معامل تصغير: لو موبايل (مش لاندسكيب) صغر العناصر بنسبة 60%
    double scale = (isMobile && !isLandscape) ? 0.4 : 1.0;
    return BlocBuilder<TimeCubit, DateTime>(
      builder: (context, state) {
        DateTime currentTime = state;

        String time = DateFormat('hh:mm', 'ar').format(currentTime);
        String seconds = DateFormat('ss', 'ar').format(currentTime);
        String amPm = DateFormat('a', 'ar').format(currentTime);
        String dayName = DateFormat('EEEE', 'ar').format(currentTime);
        String date = DateFormat('d MMMM y', 'ar').format(currentTime);
        String hijriDate = HijriCalendar.fromDate(
          currentTime,
        ).toFormat("dd MMMM yyyy هـ ");

        return Padding(
          padding: isMobile
              ? const EdgeInsets.only(left: 20, right: 20, bottom: 20)
              : isTabletDesktop
              ? const EdgeInsets.symmetric(horizontal: 40, vertical: 10)
              : const EdgeInsets.all(1),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                // SizedBox(height: 50),
                // === 1. قسم الساعة ===
                ClockSectionBuilder(
                  scale: scale,
                  seconds: seconds,
                  time: time,
                  amPm: amPm,
                ),
                SizedBox(
                  height: 25 * MediaQuery.sizeOf(context).height * 0.001,
                ),

                // === 3. قسم التاريخ ===
                Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          AppColors.silverMarble,
                          AppColors.silverMarble,
                          AppColors.silverMarble.withOpacity(0.3),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Text(
                        dayName,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: isLandscape ? 60 : 35,
                              color: Colors.white,
                              fontFamily: 'Thuluth',
                            ),
                      ),
                    ),

                    Flex(
                      direction: isWatch ? Axis.vertical : Axis.horizontal,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: isLandscape ? 30.0 : 15.0,
                      mainAxisSize: MainAxisSize.max,

                      children: [
                        Text(
                          "$date م",
                          style: GoogleFonts.cairo(
                            fontSize: isLandscape ? 30 : 16,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        if (isLandscape) ...[
                          Container(
                            height: 30,
                            width: 2,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryGold.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ] else
                          isWatch
                              ? const SizedBox.shrink()
                              : Container(
                                  height: 2,
                                  width: 15,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryGold.withOpacity(
                                      0.5,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                        Text(
                          hijriDate,
                          style: GoogleFonts.cairo(
                            fontSize: isLandscape ? 30 : 16,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ClockSectionBuilder extends StatelessWidget {
  const ClockSectionBuilder({
    super.key,
    required this.scale,
    required this.seconds,
    required this.time,
    required this.amPm,
  });

  final double scale;
  final String seconds;
  final String time;
  final String amPm;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          AppColors.lightGold,
          AppColors.secondaryGold,
          AppColors.secondaryGold.withOpacity(0.4),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.center, // سنترناها
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 80 * scale,
              child: Text(
                seconds,
                style: TextStyle(
                  fontSize: 50 * scale,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: GoogleFonts.tajawal().copyWith(
              fontSize: 200 * scale,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amPm,
            style: TextStyle(
              fontSize: 50 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
