import 'dart:async';
import 'dart:developer';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:slider_button/slider_button.dart'; // 👈 استيراد الباكيدج الجديدة
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class AdhanScreen extends StatefulWidget {
  final String? payload;
  final int? notificationId;
  final String? prayerName;

  const AdhanScreen({
    super.key,
    this.payload,
    this.notificationId,
    this.prayerName,
  });

  @override
  State<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends State<AdhanScreen> with WidgetsBindingObserver {
  Timer? _autoCloseTimer; // 👈 التايمر اللي هيقفل الشاشة

  void _closeScreen() async {
    if (mounted) {
      _autoCloseTimer?.cancel(); // تأمين إلغاء التايمر

      // 👈 إيقاف المنبه (الصوت) عن طريق باكيدج alarm
      // لو عندنا ID محدد، نوقف المنبه بتاعه. لو لأ، نوقف كل المنبهات الشغالة
      if (widget.notificationId != null) {
        await Alarm.stop(widget.notificationId!);
        log("🛑 STOPPED ADHAN ID: ${widget.notificationId}");
      } else {
        // محاولة استخراج الـ ID من الـ payload (بيجي بالشكل: adhan_5)
        final alarmId = _extractAlarmId();
        if (alarmId != null) {
          await Alarm.stop(alarmId);
        } else {
          await Alarm.stopAll();
        }
      }

      SystemNavigator.pop(); // اقفل الـ Activity بالكامل
    }
  }

  /// استخراج رقم المنبه من الـ payload (مثال: "adhan_5" -> 5)
  int? _extractAlarmId() {
    if (widget.payload == null) return null;
    log("payload : ${widget.payload}");
    final parts = widget.payload!.split('_');
    if (parts.length >= 2) {
      return int.tryParse(parts.last);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // إذا مررنا اسم الصلاة مباشرة من المنبه اللي بيرن، نستخدمه ونلغي جلب الداتا المتأخر عشان الشاشة متكتبش "الظهر" غلط
    if (widget.prayerName != null && widget.prayerName!.isNotEmpty) {
      prayerTitle = widget.prayerName;
    } else {
      _fetchRingingPrayerTitle();
    }

    _autoCloseTimer = Timer(const Duration(minutes: 4, seconds: 48), () {
      _closeScreen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      log("📡 Power button pressed or screen turned off - Stopping Adhan");
      _closeScreen();
    }
  }

  String? prayerTitle;

  /// 👈 جلب عنوان الصلاة من بيانات المنبه الشغال حالياً
  Future<void> _fetchRingingPrayerTitle() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // نجيب المنبهات اللي شغالة دلوقتي من باكيدج alarm
    final ringingAlarms = await Alarm.getAlarms();
    if (ringingAlarms.isNotEmpty) {
      // أول منبه شغال — نجيب العنوان بتاعه
      final alarm = ringingAlarms.first;
      log("prayerTitle : ${alarm.notificationSettings.title}");
      if (mounted) {
        setState(() {
          prayerTitle = alarm.notificationSettings.title;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 👈 1. سحب أبعاد الشاشة
    final size = MediaQuery.of(context).size;

    // 👈 2. تحديد نقطة كسر (Breakpoint) للشاشات الصغيرة جداً
    final bool isSmallScreen = size.height < 700;

    const Color goldColor = AppColors.lightGold;
    const Color darkBgColor = AppColors.deepBackground;

    return Scaffold(
      backgroundColor: darkBgColor,
      body: SafeArea(
        child: Padding(
          // 👈 3. حواف متجاوبة (8% من العرض و 3% من الطول)
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.08,
            vertical: size.height * 0.03,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 4. اللوجو: ارتفاعه 15% من الشاشة
              Image.asset(
                'assets/images/app_icon_transparent.png',
                height: size.height * 0.15,
              ),

              const Spacer(flex: 2), // مسافة مرنة علوية
              // 5. أيقونة المسجد: حجمها 12% من طول الشاشة
              Icon(
                Icons.mosque_outlined,
                size: size.height * 0.12,
                color: goldColor,
              ),

              SizedBox(height: size.height * 0.03),

              // 6. النصوص: أحجام خطوط متجاوبة
              Text(
                prayerTitle ?? 'حان وقت الصلاة',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isSmallScreen
                      ? 28
                      : 36, // يصغر شوية لو الشاشة قصيرة
                  fontWeight: FontWeight.bold,
                  color: goldColor,
                  textBaseline: TextBaseline.alphabetic,
                ),
              ),

              SizedBox(height: size.height * 0.01),

              Text(
                'جاري رفع الأذان...',
                style: GoogleFonts.cairo(
                  fontSize: isSmallScreen ? 18 : 22,
                  // 👈 استخدام withValues بدلاً من withOpacity (تحديث فلاتر الجديد)
                  color: goldColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(
                flex: 3,
              ), // مسافة مرنة سفلية (أكبر شوية عشان تزق الزرار لتحت)
              // 7. الـ Slider Button
              Directionality(
                textDirection: TextDirection.ltr,
                child: SliderButton(
                  action: () async {
                    _closeScreen();
                    return null;
                  },
                  label: Text(
                    "اسحب لإيقاف الأذان",
                    style: GoogleFonts.cairo(
                      color: darkBgColor,
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 16 : 18,
                    ),
                  ),
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: goldColor,
                    size: 30,
                  ),
                  baseColor: Colors.black,
                  buttonColor: darkBgColor,
                  backgroundColor: goldColor,
                  highlightedColor: Colors.black87.withAlpha(30),
                  shimmer: true,
                  vibrationFlag: true,
                  alignLabel: Alignment.center,
                  width: double.infinity,
                  // 👈 أبعاد الزرار تتجاوب مع الشاشة
                  height: isSmallScreen ? 55 : 65,
                  buttonSize: isSmallScreen ? 45 : 55,
                  radius: 50,
                ),
              ),

              SizedBox(height: size.height * 0.02), // مسافة أمان سفلية
            ],
          ),
        ),
      ),
    );
  }
}
