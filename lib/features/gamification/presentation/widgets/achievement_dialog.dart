import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/badge_model.dart';

class AchievementDialog extends StatelessWidget {
  final BadgeModel badge;

  const AchievementDialog({super.key, required this.badge});

  static void show(BuildContext context, BadgeModel badge) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AchievementDialog(badge: badge),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.screenBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Using a network Lottie or local one if exists. 
            // We use a simple placeholder or icon if Lottie isn't loaded properly
            Icon(Icons.military_tech_rounded, size: 80, color: AppColors.secondaryGold),
            const SizedBox(height: 16),
            Text(
              'وسام جديد!',
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryGold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badge.name,
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.primaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              badge.description,
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: context.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(
                'متابعة',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
