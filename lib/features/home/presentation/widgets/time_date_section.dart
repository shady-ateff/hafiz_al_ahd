import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';

class TimeDateSection extends StatelessWidget {
  const TimeDateSection({super.key, required this.isLandscape});

  final bool isLandscape;


  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TimeCubit, DateTime>(
      builder: (context, state) {
        DateTime currentTime = state;
        // --- Text Preparation ---
        // Format the current time and date components using 'intl' for localization (Arabic).
        String time = DateFormat('hh:mm', 'ar').format(currentTime);
        String seconds = DateFormat('ss', 'ar').format(currentTime);
        String amPm = DateFormat('a', 'ar').format(currentTime);
        String dayName = DateFormat('EEEE', 'ar').format(currentTime);
        String date = DateFormat('d MMMM y', 'ar').format(currentTime);
        String hijriDate = HijriCalendar.fromDate(
          currentTime,
        ).toFormat("dd MMMM yyyy هـ ");
        return Flex(
          // Use Row for landscape, Column for portrait.
          direction: isLandscape ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max, // Take up only necessary space.
          children: [
            // === 1. The Large Time Section ===
            Flexible(
              flex: 2, // Takes up more space.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,

                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      seconds,
                      style: TextStyle(
                        fontSize: 40,
                        color: AppColors.secondaryGold.withOpacity(0.8),
                      ),
                    ),

                    Text(
                      time,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 120, // Large initial font size.
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryGold, // Golden color.
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      amPm,
                      style: TextStyle(
                        fontSize: 40,
                        color: AppColors.secondaryGold.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // === 2. Separator (Visible only in landscape) ===
            if (isLandscape) ...[
              const SizedBox(width: 40),
              Container(
                height: 100, // Line height.
                width: 2, // Line thickness.
                decoration: BoxDecoration(
                  color: AppColors.secondaryGold.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 40),
            ] else
              // Vertical spacing in portrait mode.
              const SizedBox(height: 20),

            // === 3. Date and Day Section ===
            Flexible(
              flex: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: isLandscape
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(children: [TextSpan(text: hijriDate)]),
                      style: GoogleFonts.cairo(
                        fontSize: isLandscape ? 20 : 16,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 60),
              
                    // Day name (using Thuluth font if available in the theme).
                    Text(
                      dayName,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: isLandscape ? 50 : 40,
                        color: Colors.white,
                        // height: 1.2, // Adjust for Thuluth font ascenders.
                      ),
                    ),
                    // Full date.
                    SizedBox(height: isLandscape ? 16 : 8),
                    Text(
                      date,
                      style: GoogleFonts.cairo(
                        fontSize: isLandscape ? 22 : 18,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
