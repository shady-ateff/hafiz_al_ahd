import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../../domain/entities/focus_session_state.dart';
import '../../domain/entities/focus_ward_type.dart';

class FocusActiveSessionCard extends StatelessWidget {
  final FocusSessionState session;
  final VoidCallback onSnooze;
  final VoidCallback onCancel;

  const FocusActiveSessionCard({
    super.key,
    required this.session,
    required this.onSnooze,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final remainingSnooze = (session.maxSnoozeCount - session.snoozeCount)
        .clamp(0, session.maxSnoozeCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlack,
            AppColors.secondaryGold.withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondaryGold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondaryGold.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.lightGold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'جلسة تركيز جارية الآن',
                style: GoogleFonts.cairo(
                  color: AppColors.lightGold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: remainingSnooze > 0
                      ? AppColors.secondaryGold.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'الغفوة: $remainingSnooze من أصل ${session.maxSnoozeCount}',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: remainingSnooze > 0
                        ? AppColors.lightGold
                        : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            session.wardType.displayName,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.lightText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'درع الحماية نشط لحجب التطبيقات المشتتة حتى إتمام الورد المبارك.',
            style: GoogleFonts.cairo(fontSize: 12, color: AppColors.silverMarble),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
                child: Text('إلغاء الجلسة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: remainingSnooze > 0 ? onSnooze : null,
                icon: const Icon(Icons.snooze, size: 18),
                label: Text('تأجيل 5 دقائق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryGold,
                  foregroundColor: AppColors.darkText,
                  disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
