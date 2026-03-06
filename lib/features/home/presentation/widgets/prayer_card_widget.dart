import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:intl/intl.dart';

class PrayerCard extends StatefulWidget {
  final String name;
  final DateTime? time;
  final Duration? remaining;
  final IconData icon;
  final bool isWideLayout;
  final bool? isNextPrayer;

  const PrayerCard({
    super.key,
    required this.name,
    required this.time,
    required this.remaining,
    required this.icon,
    required this.isWideLayout,
    required this.isNextPrayer,
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
              child: Text(
                widget.time != null
                    ? DateFormat('hh:mm a', 'ar').format(widget.time!)
                    : '--:--',
                style: GoogleFonts.cairo(
                  color: widget.isNextPrayer == true
                      ? Colors.white
                      : AppColors.secondaryGold,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minHeight: 70, minWidth: 100),
          decoration: BoxDecoration(
            color: AppColors.primaryBlack,
            borderRadius: BorderRadius.circular(12),
            // الفريم هنا بياخد قيمة الأنيميشن المتغيرة
            border: widget.isNextPrayer == true
                ? Border.all(
                    color: AppColors.silverMarble, // لون التوهج
                    width: _animation!.value, // السُمك بيتغير من 1 لـ 4
                  )
                : Border.all(color: AppColors.secondaryGold.withAlpha(100)),
            // نقدر نضيف BoxShadow صغير بيكبر ويصغر بيدي شكل فخم جداً
            boxShadow: widget.isNextPrayer == true
                ? [
                    BoxShadow(
                      color: AppColors.silverMarble.withOpacity(0.3),
                      blurRadius: _animation!.value * 3, // التوهج بيكبر ويصغر
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: child,
        );
      },
    );
  }
}
