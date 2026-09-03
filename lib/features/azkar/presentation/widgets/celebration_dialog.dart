import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class CelebrationDialog extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onReset;

  const CelebrationDialog({
    super.key,
    required this.onContinue,
    required this.onReset,
  });

  @override
  State<CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<CelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.secondaryGold, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondaryGold.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColors.secondaryGold,
                size: 80,
              ),
              const SizedBox(height: 16),
              Text(
                'تقبل الله طاعتكم!',
                style: GoogleFonts.cairo(
                  color: context.primaryText,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'لقد أتممت قراءة الأذكار بنجاح. جعله الله في ميزان حسناتك.',
                style: GoogleFonts.cairo(
                  color: context.secondaryText,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: widget.onContinue,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppColors.secondaryGold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'العودة لقائمة الأذكار',
                  style: GoogleFonts.cairo(
                    color: AppColors.primaryBlack,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onReset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppColors.secondaryGold, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'إعادة الأذكار',
                  style: GoogleFonts.cairo(
                    color: AppColors.secondaryGold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showCelebrationDialog(
  BuildContext context, {
  required VoidCallback onContinue,
  required VoidCallback onReset,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => CelebrationDialog(
      onContinue: onContinue,
      onReset: onReset,
    ),
  );
}
