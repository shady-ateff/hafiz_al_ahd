import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/utils/app_theme.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';

/// A screen that displays the current time and date in a visually appealing,
/// responsive layout. It adapts to both portrait and landscape orientations.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use a deep, dark background for a luxurious feel.
      backgroundColor: AppColors.deepBackground,
      body: SafeArea(
        child: BlocBuilder<TimeCubit, DateTime>(
          builder: (context, currentTime) {
            // --- Text Preparation ---
            // Format the current time and date components using 'intl' for localization (Arabic).
            String time = DateFormat('hh:mm', 'ar').format(currentTime);
            String amPm = DateFormat('a', 'ar').format(currentTime);
            String dayName = DateFormat('EEEE', 'ar').format(currentTime);
            String date = DateFormat('d MMMM y', 'ar').format(currentTime);

            // --- Responsive Layout ---
            // LayoutBuilder is the key to responsiveness.
            // It provides the available screen constraints to decide on the layout.
            return LayoutBuilder(
              builder: (context, constraints) {
                // Determine if the screen is wide enough for a landscape layout.
                bool isLandscape = constraints.maxWidth > 600;

                return Center(
                  child: SingleChildScrollView(
                    // Ensures the content doesn't overflow on vertically small screens.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Flex(
                        // Use Row for landscape, Column for portrait.
                        direction: isLandscape ? Axis.horizontal : Axis.vertical,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min, // Take up only necessary space.
                        children: [
                          // === 1. The Large Time Section ===
                          Flexible(
                            flex: 2, // Takes up more space.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    time,
                                    style: Theme.of(context)
                                        .textTheme
                                        .displayLarge
                                        ?.copyWith(
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
                              width: 2,   // Line thickness.
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: isLandscape
                                  ? CrossAxisAlignment.center
                                  : CrossAxisAlignment.center,
                              children: [
                                // Day name (using Thuluth font if available in the theme).
                                Text(
                                  dayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayLarge
                                      ?.copyWith(
                                        fontSize: isLandscape ? 50 : 40,
                                        color: Colors.white,
                                        // height: 1.2, // Adjust for Thuluth font ascenders.
                                      ),
                                ),
                                // Full date.
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
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}