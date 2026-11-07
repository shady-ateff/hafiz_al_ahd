import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

/// An elegant Islamic & modern styled dialog prompting users to rate Hafiz Al-Ahd on Google Play.
class AppRatingDialog extends StatelessWidget {
  final VoidCallback onRateNow;
  final VoidCallback onRemindLater;
  final VoidCallback onNeverAskAgain;

  const AppRatingDialog({
    super.key,
    required this.onRateNow,
    required this.onRemindLater,
    required this.onNeverAskAgain,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final cardColor = context.cardBg;
    final primaryTextColor = context.primaryText;
    final secondaryTextColor = context.secondaryText;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.secondaryGold.withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.6)
                  : AppColors.secondaryGold.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Badge Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.secondaryGold.withOpacity(0.2),
                    AppColors.secondaryGold.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppColors.secondaryGold.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.star_rounded,
                color: AppColors.secondaryGold,
                size: 42,
              ),
            ),
            const SizedBox(height: 16),

            // 5 Star row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.star_rounded,
                    color: AppColors.secondaryGold,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'أكرمنا بتقييمك لتطبيق حافظ العهد',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              'إذا كان التطبيق يعينك على صلواتك وقراءتك لكتاب الله، فإن تقييمك بـ 5 نجوم على متجر Google Play يسهم في وصوله لآلاف المسلمين ويكون صدقة جارية لنا ولك بإذن الله.',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: secondaryTextColor,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Button 1: Rate Now (Primary)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onRateNow,
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: AppColors.primaryBlack,
                  size: 20,
                ),
                label: Text(
                  'تقييم الآن (5 نجوم)',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlack,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryGold,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Button 2: Remind Me Later
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: onRemindLater,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.secondaryGold.withOpacity(0.35),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'تذكيري لاحقاً',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Button 3: Don't Ask Again
            TextButton(
              onPressed: onNeverAskAgain,
              child: Text(
                'لا تسألني مجدداً',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: secondaryTextColor.withOpacity(0.7),
                  decoration: TextDecoration.underline,
                  decorationColor: secondaryTextColor.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

