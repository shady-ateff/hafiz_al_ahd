import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:slider_button/slider_button.dart'; // 👈 استيراد الباكيدج الجديدة
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/notification_repository_impl.dart';

class AdhanScreen extends StatefulWidget {
  final String? payload;
  final int? notificationId;

  const AdhanScreen({super.key, this.payload, this.notificationId});

  @override
  State<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends State<AdhanScreen> {
  Timer? _autoCloseTimer; // 👈 التايمر اللي هيقفل الشاشة
  void _closeScreen() async {
    if (mounted) {
      _autoCloseTimer?.cancel(); // تأمين إلغاء التايمر
      final repo = NotificationRepositoryImpl();
      await repo.cancelActivePrayerNotification();
      SystemNavigator.pop(); // اقفل الـ Activity بالكامل
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchRingingPrayerTitle();

    _autoCloseTimer = Timer(const Duration(minutes: 4, seconds: 48), () {
      _closeScreen();
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  String? prayerTitle;

  Future<void> _fetchRingingPrayerTitle() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final repo = NotificationRepositoryImpl();
    final activeNotifications = await repo.flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.getActiveNotifications();

    if (activeNotifications != null) {
      for (var active in activeNotifications) {
        if (active.channelId != null &&
            active.channelId!.contains('prayer_channel')) {
          if (mounted) {
            // 👈 4. لقيناه! نحدث الشاشة فوراً بالاسم الجديد
            setState(() {
              prayerTitle = active.title ?? 'حان وقت الصلاة';
            });
          }
          break; // نوقف اللوب خلاص
        }
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
                style: GoogleFonts.cairo(
                  fontSize: isSmallScreen ? 28 : 36, // يصغر شوية لو الشاشة قصيرة
                  fontWeight: FontWeight.bold,
                  color: goldColor, 
                  letterSpacing: 1.2,
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

              const Spacer(flex: 3), // مسافة مرنة سفلية (أكبر شوية عشان تزق الزرار لتحت)

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
  }}
