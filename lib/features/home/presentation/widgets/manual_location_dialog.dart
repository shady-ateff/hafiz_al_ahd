import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart'; // تأكد من المسار
import '../cubit/prayer_times_cubit/prayer_times_cubit.dart';

class ManualLocationDialog extends StatelessWidget {
  const ManualLocationDialog({super.key});

  // خريطة (Map) بأسماء المحافظات/المدن وإحداثياتها الثابتة (عشان نشتغل أوفلاين)
  static const Map<String, Map<String, double>> egyptCities = {
    'القاهرة': {'lat': 30.0444, 'lng': 31.2357},
    'الإسكندرية': {'lat': 31.2001, 'lng': 29.9187},
    'المنصورة': {'lat': 31.0379, 'lng': 31.3815},
    'طنطا': {'lat': 30.7865, 'lng': 31.0004},
    'أسيوط': {'lat': 27.1810, 'lng': 31.1837},
    'الأقصر': {'lat': 25.6872, 'lng': 32.6396},
    'أسوان': {'lat': 24.0889, 'lng': 32.8998},
    // تقدر تزود أي محافظات تانية هنا بسهولة
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.primaryBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.secondaryGold.withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الأيقونة والعنوان
            Icon(Icons.location_off_rounded, color: AppColors.errorColor, size: 40),
            const SizedBox(height: 12),
            Text(
              'تعذر تحديد الموقع!',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يرجى اختيار مدينتك يدوياً لحساب مواقيت الصلاة بدقة بدون إنترنت.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                color: AppColors.silverMarble,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // قائمة المدن (List of choices)
            SizedBox(
              height: 250, // ارتفاع ثابت عشان لو المدن كترت تعمل سكرول
              child: ListView.separated(
                itemCount: egyptCities.keys.length,
                separatorBuilder: (context, index) => Divider(
                  color: AppColors.silverMarble.withOpacity(0.2),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  String cityName = egyptCities.keys.elementAt(index);
                  double lat = egyptCities[cityName]!['lat']!;
                  double lng = egyptCities[cityName]!['lng']!;

                  return ListTile(
                    title: Text(
                      cityName,
                      style: GoogleFonts.cairo(
                        color: AppColors.secondaryGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                    onTap: () {
                      // 1. نقفل الديالوج
                      Navigator.pop(context);
                      // 2. ننادي على المايسترو (الـ Cubit) عشان يحفظ ويحسب
                      context.read<PrayerTimesCubit>().fetchPrayerTimesManually(lat, lng, cityName);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}