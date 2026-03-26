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

  const AdhanScreen({
    super.key,
    this.payload,
    this.notificationId,
  });

  @override
  State<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends State<AdhanScreen> {
  @override
  void initState() {
    super.initState();
    _fetchRingingPrayerTitle();
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
    // تحديد الألوان هنا لسهولة التعديل مستقبلاً
    const Color goldColor = AppColors.lightGold; // افترضت إن اسم اللون كده عندك
    const Color darkBgColor =
        AppColors.deepBackground; // افترضت إن اسم اللون كده عندك

    return Scaffold(
      backgroundColor: darkBgColor, // 👈 1. الخلفية سوداء سادة
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
          child: Column(
            children: [
              // 👈 2. لوجو التطبيق في الأعلى
              Image.asset(
                'assets/images/app_icon_transparent.png', // 👈 تأكد من مسار اللوجو عندك
                height: 130,
                // لو اللوجو مش شفاف، ممكن تستخدم colorBlendMode لدمجه
              ),

              const Spacer(), // توزيع مسافة مرنة
              // 👈 3. أيقونة المسجد باللون الذهبي
              const Icon(
                Icons.mosque_outlined, // شكل أجمل وأرق
                size: 120,
                color: goldColor, // 👈 ذهبي
              ),

              const SizedBox(height: 40),

              // 👈 4. النصوص باللون الذهبي
              Text(
                prayerTitle ??
                    'حان وقت الصلاة', // 👈 نص افتراضي لو ماجاش من الباي لود
                style: GoogleFonts.cairo(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: goldColor, // 👈 ذهبي
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 15),

              Text(
                'جاري رفع الأذان...',
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  color: goldColor.withOpacity(0.7), // 👈 ذهبي شفاف قليلاً
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(flex: 2), // مسافة مرنة أكبر قبل السلايدر
              // 👈 5. الـ Swipe Slider (سحب لإيقاف الأذان)
              Center(
                child: Directionality(
                  textDirection:
                      TextDirection.ltr, // عشان السحب من اليمين للشمال
                  child: SliderButton(
                    action: () async {
                      // نفس اللوجيك البرمجي بتاعك بدون تغيير
                      final repo = NotificationRepositoryImpl();
                      await repo.cancelActivePrayerNotification();
                      await Future.delayed(const Duration(milliseconds: 1000));
                      SystemNavigator.pop();
                      return null; // ضروري للباكيدج
                    },

                    /// تحسينات الشكل للـ Slider
                    label: Text(
                      "اسحب لإيقاف الأذان",
                      style: GoogleFonts.cairo(
                        color: darkBgColor, // لون النص داخل الزرار الذهبي
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    icon: const Icon(
                      Icons.stop_rounded,
                      color: goldColor, // لون الأيقونة جوه الدائرة
                      size: 35,
                    ),
                    // ألوان السلايدر
                    baseColor: Colors.black, // لون النص المتحرك
                    buttonColor: darkBgColor, // لون الدائرة التي يتم سحبها
                    backgroundColor: goldColor, // لون الخلفية الـ Track
                    highlightedColor: Colors.black87.withAlpha(30),

                    // تأثيرات إضافية
                    shimmer: true, // تأثير لمعان النص
                    vibrationFlag: true, // اهتزاز بسيط عند السحب
                    alignLabel: Alignment.center, // توسيط النص داخل الزرار
                    width: double.infinity, // يأخذ عرض الشاشة المتاح
                    height: 65,
                    radius: 50,
                    // dismissible: false, // لا يختفي بعد السحب
                  ),
                ),
              ),

              const SizedBox(height: 20), // مسافة أمان سفلية
            ],
          ),
        ),
      ),
    );
  }
}
