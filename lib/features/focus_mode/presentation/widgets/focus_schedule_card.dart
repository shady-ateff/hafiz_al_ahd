import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../../domain/entities/focus_schedule.dart';
import '../../domain/entities/focus_ward_type.dart';

class FocusScheduleCard extends StatelessWidget {
  final FocusSchedule schedule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditTime;
  final VoidCallback? onEditGoal;

  const FocusScheduleCard({
    super.key,
    required this.schedule,
    required this.onToggle,
    required this.onEditTime,
    this.onEditGoal,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(schedule.hour, schedule.minute);
    final iconData = _getWardIcon(schedule.wardType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: schedule.isEnabled
              ? AppColors.secondaryGold.withOpacity(0.5)
              : Colors.white10,
        ),
        boxShadow: schedule.isEnabled
            ? [
                BoxShadow(
                  color: AppColors.secondaryGold.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: schedule.isEnabled ? AppColors.goldenGradient : null,
              color: schedule.isEnabled ? null : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              iconData,
              color: schedule.isEnabled ? AppColors.darkText : Colors.grey,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.title,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: onEditTime,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondaryGold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit,
                              size: 13,
                              color: AppColors.secondaryGold,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDays(schedule.daysOfWeek),
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
                if (schedule.targetQuranGoal != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onEditGoal,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryGold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'الهدف: ${_formatGoal(schedule)}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.lightGold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.edit,
                            size: 11,
                            color: AppColors.lightGold,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: schedule.isEnabled,
            onChanged: onToggle,
            activeColor: AppColors.lightGold,
            activeTrackColor: AppColors.secondaryGold.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    final isPm = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMin = minute.toString().padLeft(2, '0');
    final suffix = isPm ? 'م' : 'ص';
    return '$displayHour:$displayMin $suffix';
  }

  String _formatDays(List<int> days) {
    if (days.length == 7) return 'يوميًا';
    return '${days.length} أيام أسبوعيًا';
  }

  String _formatGoal(FocusSchedule schedule) {
    final g = schedule.targetQuranGoal!;
    return 'قراءة ${g.targetValue} صفحة';
  }

  IconData _getWardIcon(FocusWardType type) {
    switch (type) {
      case FocusWardType.morningAzkar:
        return Icons.wb_sunny_outlined;
      case FocusWardType.eveningAzkar:
        return Icons.nightlight_round;
      case FocusWardType.postPrayerAzkar:
        return Icons.access_time;
      case FocusWardType.quranReading:
        return Icons.menu_book;
      case FocusWardType.custom:
        return Icons.alarm;
    }
  }
}
