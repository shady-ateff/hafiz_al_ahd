import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
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
          end: 4.0, // سُمك الفريم وهو منور
        ).animate(
          CurvedAnimation(
            parent: _animationController!,
            curve: Curves.easeInOut, // عشان الحركة تبقى ناعمة
          ),
        );

    // لو الكارت ده بتاع الصلاة الجاية أول ما الشاشة تفتح، شغله
    if (widget.isNextPrayer == true) {
      _animationController!.repeat(
        reverse: true,
      ); // 👈 ده اللي هيخليه ينبض ميقفش!
    }
  }

  // 👈 دالة المراقبة (خطوة 4 اللي سألت عليها)
  @override
  void didUpdateWidget(covariant PrayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // لو الكارت ده لسه طازة متحدث وبقى هو الصلاة الجاية
    if (widget.isNextPrayer == true && oldWidget.isNextPrayer != true) {
      _animationController!.repeat(reverse: true);
    }
    // لو الكارت ده مابقاش هو الصلاة الجاية (خلاص الأذان أذن)
    else if (widget.isNextPrayer != true && oldWidget.isNextPrayer == true) {
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
    return AnimatedBuilder(
      animation: _animation!,
      child: Flex(
        direction: widget.isWideLayout ? Axis.horizontal : Axis.vertical,
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
                  Icon(
                    widget.icon,
                    // خلينا الأيقونة تنور أبيض لو دي الصلاة الجاية
                    color: widget.isNextPrayer == true
                        ? Colors.white
                        : AppColors.secondaryGold,
                    size: 28,
                  ),
                  Text(
                    widget.name,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
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
                  Text(
                    widget.displayTime != null
                        ? DateFormat(
                            'hh:mm a',
                            'ar',
                          ).format(widget.displayTime!)
                        : '--:--',
                    style: GoogleFonts.cairo(
                      color: AppColors.secondaryGold,
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
      builder: (context, child) {
        return Container(
          // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minHeight: 70, minWidth: 100),
          decoration: BoxDecoration(
            color: AppColors.deepBackground,
            borderRadius: BorderRadius.circular(12),
            // الفريم هنا بياخد قيمة الأنيميشن المتغيرة
            border: widget.isIqama
                ? Border.all(
                    color: AppColors.errorColor,
                    width: _animation!.value,
                  )
                : widget.isNextPrayer == true
                ? Border.all(
                    color: AppColors.silverMarble,
                    width: _animation!.value,
                  )
                : Border.all(color: AppColors.secondaryGold.withAlpha(50)),
            boxShadow: widget.isNextPrayer == true
                ? [
                    BoxShadow(
                      color: AppColors.silverMarble.withOpacity(0.3),
                      blurRadius: _animation!.value * 5, // التوهج بيكبر ويصغر
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            alignment: Alignment.topLeft,
            children: [
              Center(child: child!),
              if (widget.isNextPrayer == true)
                Positioned(
                  top: 6,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isIqama
                          ? AppColors.errorColor.withOpacity(
                              0.8,
                            ) // أحمر واضح للإقامة
                          : AppColors.silverMarble.withOpacity(
                              0.2,
                            ), // فضي شفاف للصلاة
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: NextPrayerTimer(
                      targetTime: widget.time,
                      isIqama: widget.isIqama,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class NextPrayerTimer extends StatelessWidget {
  const NextPrayerTimer({super.key, this.targetTime, this.isIqama = false});

  final DateTime? targetTime;
  final bool isIqama;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TimeCubit, DateTime>(
      builder: (context, currentTime) {
        Duration remaining =
            targetTime?.difference(currentTime) ?? Duration.zero;

        if (remaining.isNegative) remaining = Duration.zero;

        String prefix = isIqama ? 'إقامة' : '-';
        Color textColor = isIqama
            ? Colors.white
            : AppColors.silverMarble; // خليتها أبيض للإقامة عشان تبان أحسن

        return Text(
          isIqama
              ? '$prefix ${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}'
              : '$prefix ${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
          style: GoogleFonts.cairo(
            color: textColor,
            // fontSize: 12, // 👈 السر هنا: الخط صغر عشان يكفي جوه الكبسولة
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}
