import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class DailyAzkarCard extends StatelessWidget {
  final String title;
  final String count;
  final IconData icon;
  final VoidCallback? onTap; // 👈 1. ضفنا دالة الضغط

  const DailyAzkarCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    this.onTap, // 👈 استقبلناها هنا
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // الـ Container الخارجي للحدود والخلفية بس
      decoration: BoxDecoration(
        color: AppColors.deepBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondaryGold.withOpacity(0.15),
          width: 1,
        ),
      ),
      // 👈 2. الـ Material والـ InkWell عشان الـ Ripple Effect
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.secondaryGold.withOpacity(0.1),
          highlightColor: AppColors.secondaryGold.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24), // 👈 3. الـ Padding بقى جوه
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGold.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.lightGold, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count,
                  style: GoogleFonts.cairo(
                    color: AppColors.lightGold.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}