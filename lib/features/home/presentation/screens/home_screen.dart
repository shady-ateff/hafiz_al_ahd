import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
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
        child: BlocBuilder<TimeCubit, DateTime>(
          builder: (context, currentTime) {
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
                      child: Column(
                        children: [
                          SizedBox(height: 60),
                          // === 1. Time and Date Section ===
                          Flex(
                            // Use Row for landscape, Column for portrait.
                            direction: isLandscape
                                ? Axis.horizontal
                                : Axis.vertical,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize
                                .min, // Take up only necessary space.
                            children: [
                              // === 1. The Large Time Section ===
                              Flexible(
                                flex: 2, // Takes up more space.
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,

                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        seconds,
                                        style: TextStyle(
                                          fontSize: 40,
                                          color: AppColors.secondaryGold
                                              .withOpacity(0.8),
                                        ),
                                      ),

                                      Text(
                                        time,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displayLarge
                                            ?.copyWith(
                                              fontSize:
                                                  120, // Large initial font size.
                                              fontWeight: FontWeight.bold,
                                              color: AppColors
                                                  .secondaryGold, // Golden color.
                                              height: 1.0,
                                            ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        amPm,
                                        style: TextStyle(
                                          fontSize: 40,
                                          color: AppColors.secondaryGold
                                              .withOpacity(0.8),
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
                                    color: AppColors.secondaryGold.withOpacity(
                                      0.5,
                                    ),
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
                                    Text.rich(
                                      TextSpan(
                                        children: [TextSpan(text: hijriDate)],
                                      ),
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
                            ],
                          ),
                          const SizedBox(height: 60),
                          // === 4. Prayer Times Section ===
                          BlocBuilder<PrayerTimesCubit, PrayerTimesStates>(
                            builder: (context, state) {
                              log('state: $state');
                              if (state is PrayerTimesLoading ||
                                  state is PrayerTimesInitial) {
                                return const CircularProgressIndicator();
                              }
                              if (state is PrayerTimesError) {
                                return Text(
                                  state.message,
                                  style: const TextStyle(color: Colors.red),
                                );
                              }
                                  final prayerTimeList = state is PrayerTimesLoaded
                                      ? _getPrayersList(
                                          state.prayerTimes,
                                        )
                                      : null;
                              return
                               GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 7.5,
                                ),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: 6,
                                itemBuilder: (context, index) {
                                  final prayerTime = prayerTimeList?[index];

                                  return _buildPrayerItem(prayerTime!);
                                },
                              );
                            },
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

List<Map<String, dynamic>> _getPrayersList(PrayerTimesEntity times) {
  return [
    {'name': 'الفجر', 'time': times.fajr, 'icon': Icons.nightlight_round},
    {'name': 'الشروق', 'time': times.sunrise, 'icon': Icons.wb_sunny_outlined},
    {'name': 'الظهر', 'time': times.dhuhr, 'icon': Icons.wb_sunny},
    {'name': 'العصر', 'time': times.asr, 'icon': Icons.wb_cloudy_outlined},
    {'name': 'المغرب', 'time': times.maghrib, 'icon': Icons.wb_twilight},
    {'name': 'العشاء', 'time': times.isha, 'icon': Icons.nights_stay},
  ];
}

Widget _buildPrayerItem(Map<String, dynamic> prayerTime) {
  return Container(
    // 1. مسافات خارجية تفصل الكروت عن بعض
    margin: const EdgeInsets.only(bottom: 12), 
    
    // 2. مسافات داخلية عشان الكلام ميبقاش لازق في الحيطة
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    
    // 3. الزخرفة (لون الكارت + البرواز الذهبي + الظل)
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E1E), // لون رمادي غامق فخم
      borderRadius: BorderRadius.circular(12), // حواف ناعمة
      border: Border.all(
        color: const Color(0xFFD4AF37).withOpacity(0.3), // برواز ذهبي خفيف
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2), // ظل خفيف
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    
    // 4. ترتيب العناصر (أيقونة واسم يمين ... وقت شمال)
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // يرمي كل واحد في طرف
      children: [
        // اليمين: الأيقونة + الاسم
        Row(
          children: [
            Icon(prayerTime['icon'], color: const Color(0xFFD4AF37), size: 24),
            const SizedBox(width: 12),
            Text(
              '${prayerTime['name']}',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        
        // اليسار: الوقت (الهدف)
        Text(
          prayerTime['time'] != null 
              ? DateFormat('hh:mm a', 'ar').format(prayerTime['time']) 
              : '--:--',
          style: GoogleFonts.cairo( // خط Cairo للأرقام أوضح
            fontSize: 20,
            color: const Color(0xFFD4AF37), // ذهبي
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}