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
    double scale = isLandscape ? 1.0 : 0.6;

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
          child: Flex(
            direction: isLandscape ? Axis.horizontal : Axis.vertical,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              // === 1. قسم الساعة ===
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.center, // سنترناها
                    children: [
                      Text(
                        seconds,
                        style: TextStyle(
                          fontSize: 40 * scale, // 👈 تصغير
                          color: AppColors.secondaryGold.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: 120 * scale, // 👈 تصغير الخط الضخم
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondaryGold,
                              height: 1.0,
                              fontFamily: 'Thuluth', // تأكد إن الخط ده موجود
                            ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        amPm,
                        style: TextStyle(
                          fontSize: 40 * scale, // 👈 تصغير
                          color: AppColors.secondaryGold.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // === 2. الفاصل ===
              if (isLandscape) ...[
                const SizedBox(width: 40),
                Container(
                  height: 100,
                  width: 2,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGold.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 40),
              ] else
                // مسافة رأسية صغيرة في الموبايل بدل المسافات الكبيرة
                const SizedBox(height: 10),

              // === 3. قسم التاريخ ===
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: isLandscape ? 20.0 : 10.0,
                    children: [
                      Text(
                        dayName,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: isLandscape
                                  ? 50
                                  : 35, // 👈 تصغير اسم اليوم
                              color: Colors.white,
                              fontFamily: 'Thuluth',
                            ),
                      ),
                
                      Flex(
                        direction: isWatch ? Axis.vertical : Axis.horizontal,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        spacing: isLandscape ? 20.0 : 15.0,
                        mainAxisSize: MainAxisSize.max,
                
                        children: [
                          Text(
                            "$date م",
                            style: GoogleFonts.cairo(
                              fontSize: isLandscape ? 22 : 16,
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
                            isWatch?
                            const SizedBox.shrink()
                            : Container(
                              height: 2,
                              width: 15,
                              decoration: BoxDecoration(
                                color: AppColors.secondaryGold.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          Text(
                            hijriDate,
                            style: GoogleFonts.cairo(
                              fontSize: isLandscape ? 20 : 16,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
