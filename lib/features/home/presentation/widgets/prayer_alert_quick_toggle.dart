import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/prayer_alarm_settings_screen.dart';

/// 1-Tap Quick Control widget for Home Prayer Cards.
/// Toggles between Alarm <-> Notification.
/// Adheres strictly to the 48x48dp accessible bounding box and Arabic semantic labeling.
class PrayerAlertQuickToggle extends StatefulWidget {
  final PrayerId? prayerId;
  final String prayerName;
  final DateTime? scheduledEpoch;

  const PrayerAlertQuickToggle({
    super.key,
    required this.prayerId,
    required this.prayerName,
    this.scheduledEpoch,
  });

  @override
  State<PrayerAlertQuickToggle> createState() => _PrayerAlertQuickToggleState();
}

class _PrayerAlertQuickToggleState extends State<PrayerAlertQuickToggle> {
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    // 🌅 Rule 1: Sunrise suppression
    if (widget.prayerId == null || widget.prayerName == 'الشروق') {
      return const SizedBox.shrink();
    }

    final prayerId = widget.prayerId!;

    return BlocBuilder<PrayerAlarmSettingsCubit, PrayerAlarmSettingsState>(
      buildWhen: (prev, curr) {
        return prev.getEffectiveMode(prayerId) !=
                curr.getEffectiveMode(prayerId) ||
            prev.isTransitioning(prayerId) != curr.isTransitioning(prayerId);
      },
      builder: (context, state) {
        final isTransitioning = state.isTransitioning(prayerId);
        final effectiveMode = state.getEffectiveMode(prayerId);

        if (isTransitioning) {
          return Semantics(
            label: 'جاري تحديث وضع التنبيه لصلاة ${widget.prayerName}...',
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.secondaryGold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final IconData iconData;
        final Color iconColor;
        final String semanticLabel;

        switch (effectiveMode) {
          case PrayerAlarmType.alarm:
            iconData = Icons.notifications_active_rounded;
            iconColor = AppColors.secondaryGold;
            semanticLabel =
                'صلاة ${widget.prayerName}: وضع الأذان الكامل مفعّل. اضغط للتحويل إلى إشعار بسيط';
            break;

          case PrayerAlarmType.notification:
            iconData = Icons.notifications_none_rounded;
            iconColor =
                Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
            semanticLabel =
                'صلاة ${widget.prayerName}: وضع الإشعار البسيط مفعّل. اضغط للتحويل إلى الأذان الكامل';
            break;

          case PrayerAlarmType.off:
            iconData = Icons.notifications_off_outlined;
            iconColor = Colors.grey.withOpacity(0.6);
            semanticLabel =
                'صلاة ${widget.prayerName}: التنبيهات معطلة بالكامل. اضغط لفتح الإعدادات';
            break;
        }

        return Semantics(
          label: semanticLabel,
          button: true,
          child: IconButton(
            tooltip: semanticLabel,
            // iconSize: 20,
            padding: EdgeInsets.zero,
            // constraints: const BoxConstraints.tightFor(width: 20, height: 24),
            icon: Icon(iconData, color: iconColor),
            onPressed: () => _handleTap(context, effectiveMode),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              padding: WidgetStateProperty.all(EdgeInsets.zero),
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(BuildContext context, PrayerAlarmType currentMode) {
    // Rapid tapping debounce policy (1.5 seconds)
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 1500) {
      return;
    }
    _lastTapTime = now;

    if (currentMode == PrayerAlarmType.off) {
      // Off Mode interaction: surface informative SnackBar with direct navigation
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: const Color(0xFF2C2C2E),
          content: Text(
            'التنبيه معطل بالكامل لصلاة ${widget.prayerName}. يمكنك تفعيله من الإعدادات.',
            style: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
          ),
          action: SnackBarAction(
            label: 'الإعدادات',
            textColor: AppColors.secondaryGold,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrayerAlarmSettingsScreen(),
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    // Toggle Alarm <-> Notification
    context.read<PrayerAlarmSettingsCubit>().toggleAlertMode(
      widget.prayerId!,
      scheduledEpoch: widget.scheduledEpoch,
    );
  }
}
