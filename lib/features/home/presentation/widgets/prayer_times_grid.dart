import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/next_pray_time.dart'; // تأكد من المسار
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/widgets/prayer_card_widget.dart';

import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';

class PrayerTimesGrid extends StatelessWidget {
  final int crossAxisCount;
  final bool isScrollable;
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
        int rowCount = (prayers.length / crossAxisCount).ceil();

        // نحتاج لجلب الإعدادات المحفوظة من الـ SharedPreferences لعرض أوقات الإقامة الدقيقة
        // بنستخدم FutureBuilder عشان نقرأ الإعدادات لأنها Future
        return FutureBuilder<Map<String, int>>(
          future: GetIqamaDelaysUseCase().execute(),
          builder: (context, snapshot) {
            // أثناء تحميل الإعدادات، نستخدم الـ defaults مؤقتاً
            final iqamaDelays =
                snapshot.data ??
                {
                  'fajr': 25,
                  'shurooq': 0,
                  'dhuhr': 15,
                  'asr': 15,
                  'maghrib': 10,
                  'isha': 15,
                };

            // 👈 المحرك السحري: ده اللي هيخلي الشبكة تعمل Switch وقت الأذان والإقامة
            return BlocSelector<TimeCubit, DateTime, String>(
              selector: (currentTime) {
                final next = state.prayerTimes.getNextPrayer(
                  currentTime,
                  iqamaDelays: iqamaDelays,
                );
                // لو اسم الصلاة أو حالة الإقامة اتغيرت، اعمل Rebuild للشبكة فوراً
                return "${next.name}_${next.isIqama}";
              },
              builder: (context, triggerValue) {
                // بنجيب الصلاة (الجديدة) بعد ما الـ Trigger اشتغل
                final nextPrayer = state.prayerTimes.getNextPrayer(
                  DateTime.now(),
                  iqamaDelays: iqamaDelays,
                );

                if (isScrollable) {
                  return Column(
                    children: List.generate(rowCount, (rowIndex) {
                      return Row(
                        children: List.generate(crossAxisCount, (colIndex) {
                          int itemIndex =
                              (rowIndex * crossAxisCount) + colIndex;
                          if (itemIndex < prayers.length) {
                            return Expanded(
                              child: _buildFlexCard(
                                data: prayers[itemIndex],
                                isWideLayout: crossAxisCount == 1,
                                nextPrayer: nextPrayer, // 👈 بنبعت الأوبجكت كله
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
                          int itemIndex =
                              (rowIndex * crossAxisCount) + colIndex;

                          if (itemIndex < prayers.length) {
                            return Expanded(
                              child: _buildFlexCard(
                                data: prayers[itemIndex],
                                isWideLayout: forceVerticalCardLayout
                                    ? !forceVerticalCardLayout
                                    : crossAxisCount == 1,
                                nextPrayer: nextPrayer, // 👈 بنبعت الأوبجكت كله
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
          },
        );
      },
    );
  }

  Widget _buildFlexCard({
    required Map<String, dynamic> data,
    required bool isWideLayout,
    required NextPrayerTime nextPrayer, // 👈 استقبلنا الأوبجكت
  }) {
    // هل الكارت اللي بيتبني دلوقتي هو كارت الصلاة القادمة؟
    bool isThisCardNext = nextPrayer.name == data['name'];

    return PrayerCard(
      name: data['name'],
      displayTime: data['time'], // وقت العرض الثابت
      // 👈 لو ده كارت الصلاة الجاية، ابعتله وقت الهدف (ممكن يبقى الإقامة)، غير كده ابعتله الوقت العادي
      time: isThisCardNext ? nextPrayer.time : data['time'],
      icon: data['icon'],
      isWideLayout: isWideLayout,
      isNextPrayer: isThisCardNext,
      isIqama: isThisCardNext
          ? nextPrayer.isIqama
          : false, // 👈 جبناها من المصدر الصح
      remaining: null,
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
