import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_icon.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:intl/intl.dart';

class PrayerCard extends StatefulWidget {
  final String name;
  final DateTime? displayTime;
  final DateTime? time;
  final Duration? remaining;
  final IconData icon;
  final bool isWideLayout;
  final bool? isNextPrayer;
  final bool isIqama;
  final Color? activeTextColor;

  const PrayerCard({
    super.key,
    required this.name,
    required this.displayTime,
    required this.remaining,
    required this.icon,
    required this.isWideLayout,
    required this.isNextPrayer,
    required this.time,
    this.isIqama = false,
    this.activeTextColor,
  });

  @override
  State<PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends State<PrayerCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _animation =
        Tween<double>(
          begin: 1.0, // سُمك الفريم العادي
          end: 5.0, // سُمك الفريم وهو منور
        ).animate(
          CurvedAnimation(
            parent: _animationController!,
            curve: Curves.easeInOut,
          ),
        );

    if (widget.isNextPrayer == true) {
      _animationController!.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PrayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isNextPrayer == true && oldWidget.isNextPrayer != true) {
      _animationController!.repeat(reverse: true);
    } else if (widget.isNextPrayer != true && oldWidget.isNextPrayer == true) {
      _animationController!.stop();
      _animationController!.reset();
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 👈 1. قراءة حالة الثيم
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<TimeCubit, DateTime>(
      builder: (context, currentTime) {
        Duration remaining =
            widget.time?.difference(currentTime) ?? Duration.zero;

        // --- تحديد المراحل الثلاثة ---
        bool isIqama = widget.isIqama;
        bool isNextPrayer = widget.isNextPrayer == true;
        // المرحلة 2: هل متبقي 30 دقيقة أو أقل (ولسه مأذنش)؟
        bool isWithinHalfHour =
            isNextPrayer &&
            !isIqama &&
            remaining.inMinutes <= 30 &&
            !remaining.isNegative;

        // --- توزيع الألوان بناءً على المرحلة ---
        Color cardColor;
        Color borderColor;
        Color textColor;
        Color badgeColor;

        if (isIqama) {
          // 🔴 Phase 3: Iqama
          cardColor =
              AppColors.iqamaWarning; // لون برتقالي محروق (بيليق في الوضعين)
          borderColor = Colors.deepOrange.shade400;
          textColor = Colors.white;
          badgeColor = Colors.white24;
        } else if (isWithinHalfHour) {
          // 🟡 Phase 2: Within 30 min
          cardColor = AppColors.lightGold; // لون ذهبي (بيليق في الوضعين)
          borderColor = Colors.amber.shade200;
          textColor = AppColors.primaryBlack;
          badgeColor = Colors.black12;
        } else if (isNextPrayer) {
          // ⚫ Phase 1: Next prayer normal
          cardColor = context.cardBg;
          borderColor = Colors.amber;
          textColor = context.primaryText; // 👈 بيقلب أسود أو أبيض أوتوماتيك
          badgeColor = Colors.amber.withOpacity(0.15);
        } else {
          // ⚪ Normal inactive card
          cardColor = context.cardBg; // 👈 بيقلب كريمي أو أسود أوتوماتيك
          borderColor = context.borderSubtle;
          textColor = context.secondaryText;
          badgeColor = Colors.transparent;
        }

        return AnimatedBuilder(
          animation: _animation!,
          builder: (context, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              margin: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minHeight: 70, minWidth: 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cardColor, cardColor.withOpacity(0.9)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: (isNextPrayer && !isWithinHalfHour && !isIqama)
                    ? Border.all(
                        color: borderColor,
                        width: _animation!.value / 1.5,
                      )
                    : Border.all(color: borderColor, width: _animation!.value),
                boxShadow: (isNextPrayer && !isWithinHalfHour && !isIqama)
                    ? [
                        BoxShadow(
                          color: Colors.amber.withOpacity(
                            isDark ? 0.3 : 0.15,
                          ), // 👈 خففنا الوهج شوية في النهاري عشان يبان شيك
                          blurRadius: _animation!.value * 3,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                alignment: Alignment.topLeft,
                children: [
                  Center(
                    child: Flex(
                      direction: widget.isWideLayout
                          ? Axis.horizontal
                          : Axis.vertical,
                      mainAxisAlignment: widget.isWideLayout
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            clipBehavior: Clip.antiAlias,
                            child: Flex(
                              direction: widget.isWideLayout
                                  ? Axis.horizontal
                                  : Axis.vertical,
                              spacing: widget.isWideLayout ? 12.0 : 6.0,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                isNextPrayer
                                    ? Icon(
                                        widget.icon,
                                        color: textColor,
                                        size: 28,
                                      )
                                    // 👈 أيقونة الكارت غير النشط
                                    : isDark
                                    ? GradientIcon(icon: widget.icon, size: 28)
                                    : Icon(
                                        widget.icon,
                                        color: AppColors.secondaryGold,
                                        size: 28,
                                      ),

                                // 👈 2. التعديل الجوهري للتباين
                                isNextPrayer
                                    ? Text(
                                        widget.name,
                                        style: GoogleFonts.cairo(
                                          color: textColor,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : isDark
                                    ? GradientText(
                                        widget.name,
                                        gradient: AppColors.silverGradient,
                                        style: GoogleFonts.cairo(
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : Text(
                                        widget.name,
                                        style: GoogleFonts.cairo(
                                          color: context.secondaryText,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                        Flexible(
                          fit: FlexFit.loose,
                          flex: widget.isWideLayout ? 3 : 1,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Flex(
                              direction: widget.isWideLayout
                                  ? Axis.horizontal
                                  : Axis.vertical,
                              spacing: widget.isWideLayout ? 12.0 : 6.0,
                              children: [
                                isNextPrayer
                                    ? Text(
                                        widget.displayTime != null
                                            ? DateFormat(
                                                'hh:mm a',
                                                'ar',
                                              ).format(widget.displayTime!)
                                            : '--:--',
                                        style: GoogleFonts.cairo(
                                          color: textColor,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : isDark
                                    ? GradientText(
                                        widget.displayTime != null
                                            ? DateFormat(
                                                'hh:mm a',
                                                'ar',
                                              ).format(widget.displayTime!)
                                            : '--:--',
                                        gradient: AppColors.silverGradient,
                                        style: GoogleFonts.cairo(
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : Text(
                                        widget.displayTime != null
                                            ? DateFormat(
                                                'hh:mm a',
                                                'ar',
                                              ).format(widget.displayTime!)
                                            : '--:--',
                                        style: GoogleFonts.cairo(
                                          color: context.secondaryText,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // كبسولة الوقت الطايرة
                  if (isNextPrayer)
                    Positioned(
                      top: 6,
                      left: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 800),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: NextPrayerTimer(
                          targetTime: widget.time,
                          isIqama: isIqama,
                          textColor: textColor,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class NextPrayerTimer extends StatelessWidget {
  const NextPrayerTimer({
    super.key,
    this.targetTime,
    this.isIqama = false,
    required this.textColor,
  });

  final DateTime? targetTime;
  final bool isIqama;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TimeCubit, DateTime>(
      builder: (context, currentTime) {
        Duration remaining =
            targetTime?.difference(currentTime) ?? Duration.zero;
        if (remaining.isNegative) remaining = Duration.zero;
        String prefix = isIqama ? 'إقامة' : '-';

        return Text(
          isIqama
              ? '$prefix ${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}'
              : '$prefix ${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
          style: GoogleFonts.cairo(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}
