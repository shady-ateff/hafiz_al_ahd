import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String countBadge;
  final IconData icon;
  final VoidCallback? onTap; // 👈 1. ضفنا الـ Callback عشان الكارت يشتغل كزرار

  const CategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.countBadge,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // 👈 2. الـ Container الخارجي بيمسك الشكل العام والحدود
      decoration: BoxDecoration(
        color: AppColors.deepBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondaryGold.withOpacity(0.05),
          width: 1,
        ),
      ),
      // 👈 3. ضفنا Material بخلفية شفافة عشان الـ InkWell يشتغل صح جوه الـ Container
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          // 👈 4. لون الضغطة (Ripple Effect) هيبقى ذهبي خفيف جداً يدي إحساس Premium
          splashColor: AppColors.secondaryGold.withOpacity(0.1),
          highlightColor: AppColors.secondaryGold.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16), // الـ Padding اتنقل هنا
            child: Row(
              children: [
                // 1. Icon Container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.lightGold, size: 24),
                ),
                const SizedBox(width: 16),

                // 2. Titles (Middle)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.cairo(
                          color: AppColors.silverMarble.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Badge & Arrow
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    countBadge,
                    style: GoogleFonts.cairo(
                      color: AppColors.lightGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.silverMarble.withAlpha(50),
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
