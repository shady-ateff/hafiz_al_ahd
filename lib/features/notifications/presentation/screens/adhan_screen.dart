import 'dart:async';
import 'dart:developer';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:slider_button/slider_button.dart';
import 'package:audioplayers/audioplayers.dart'; // 👈 لاستخراج مدة الصوت ديناميكياً
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
  Timer? _autoCloseTimer; // 👈 التايمر اللي هيقفل الشاشة بناءً على مدة الصوت
  Timer? _checkExternalStopTimer; // 👈 لمراقبة لو اليوزر قفل الأذان من الإشعار
  bool _isClosing = false; // لمنع تكرار الإغلاق

  void _closeScreen() async {
    if (_isClosing) return;
    if (mounted) {
      _isClosing = true;
      _autoCloseTimer?.cancel(); // تأمين إلغاء التايمر
      _checkExternalStopTimer?.cancel(); // تأمين إلغاء تايمر المراقبة

      // 👈 إيقاف المنبه (الصوت) عن طريق باكيدج alarm
      if (widget.notificationId != null) {
        await Alarm.stop(widget.notificationId!);
        log("🛑 STOPPED ADHAN ID: ${widget.notificationId}");
      } else {
        // محاولة استخراج الـ ID من الـ payload (بيجي بالشكل: adhan_5)
        final alarmId = _extractAlarmId();
        if (alarmId != null) {
          await Alarm.stop(alarmId);
          log("🛑 STOPPED ADHAN from payload ID: $alarmId");
        } else {
          await Alarm.stopAll();
          log("🛑 STOPPED ALL ADHAN alarms (no ID found)");
        }
      }

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        SystemNavigator.pop();
      }
    }
  }

  /// استخراج رقم المنبه من الـ payload (مثال: "adhan_5_الفجر" -> 5)
  int? _extractAlarmId() {
    if (widget.payload == null) return null;
    final parts = widget.payload!.split('_');
    if (parts.length >= 2) {
      return int.tryParse(parts[1]);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 👈 إضافة المراقب

    // إذا مررنا اسم الصلاة مباشرة من المنبه، نستخدمه
    if (widget.prayerName != null && widget.prayerName!.isNotEmpty) {
      prayerTitle = widget.prayerName;
    }

    // دايماً بنعمل فحص للمنبه الشغال عشان نجيب مسار الصوت منه لضبط التايمر
    _fetchRingingAlarmData();

    // 👈 تايمر كل ثانيتين يفحص لو الأذان اتقفل من الإشعار الخارجي عشان يقفل الشاشة
    _checkExternalStopTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final alarms = await Alarm.getAlarms();
      bool anyRinging = false;
      for (var alarm in alarms) {
        if (await Alarm.isRinging(alarm.id)) {
          anyRinging = true;
          break;
        }
      }
      
      if (!anyRinging && mounted) {
        log("🛑 All alarms stopped externally. Closing screen.");
        _closeScreen();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // لو اليوزر داس زرار الباور (الشاشة قفلت) أو داس زرار الهوم (التطبيق نزل في الخلفية)
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      log("🛑 App went to background (Power/Home pressed). Cancelling Adhan!");
      _closeScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 👈 إزالة المراقب
    _autoCloseTimer?.cancel();
    _checkExternalStopTimer?.cancel();
    super.dispose();
  }

  String? prayerTitle;

  /// إعداد التايمر ديناميكياً بقراءة طول الملف الصوتي الحقيقي (حل جذري)
  Future<void> _setupDynamicCloseTimer(String assetPath) async {
    final player = AudioPlayer();
    try {
      String relativePath = assetPath;
      if (relativePath.startsWith('assets/')) {
        relativePath = relativePath.substring(7); // إزالة assets/ لأن audioplayers بيفهمها ضمناً
      }

      await player.setSource(AssetSource(relativePath));
      
      // محاولة سحب الطول مباشرة
      Duration? duration = await player.getDuration();
      
      // لو النظام مرجعش الطول فوراً، نستنى الـ Stream لمدة ثانيتين كحد أقصى عشان التطبيق ميهنجش
      if (duration == null) {
        try {
          duration = await player.onDurationChanged.first.timeout(const Duration(seconds: 2));
        } catch (_) {
          log("⚠️ Timeout waiting for onDurationChanged");
        }
      }

      // لو لسه مرجعش الطول (بعض أجهزة أندرويد بتحتاج تشغل الصوت الأول)، هنشغله صامت لحظة واحدة عشان يقراه
      if (duration == null) {
        log("⚠️ Forcing audio load to get dynamic duration...");
        await player.setVolume(0.0);
        await player.play(AssetSource(relativePath));
        await Future.delayed(const Duration(milliseconds: 200));
        duration = await player.getDuration();
        await player.stop();
      }

      if (duration != null && duration.inSeconds > 0 && mounted) {
        // إضافة 5 ثواني Margin لضمان انتهاء الصوت بالكامل
        final closeDuration = duration + const Duration(seconds: 5);
        _autoCloseTimer?.cancel();
        _autoCloseTimer = Timer(closeDuration, () {
          if (mounted) _closeScreen();
        });
        log("🕒 Dynamic auto-close timer set for ${closeDuration.inSeconds} seconds.");
      } else {
        _setStaticFallbackTimer(assetPath);
      }
    } catch (e) {
      log("❌ Error fetching dynamic audio duration: $e");
      _setStaticFallbackTimer(assetPath);
    } finally {
      await player.dispose();
    }
  }

  void _setStaticFallbackTimer(String assetPath) {
    int durationInSeconds = 215; 
    if (assetPath.contains('fajr_azan')) {
      durationInSeconds = 245; 
    }
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(Duration(seconds: durationInSeconds), () {
      if (mounted) _closeScreen();
    });
    log("🕒 Static fallback timer used: $durationInSeconds seconds.");
  }

  /// 👈 جلب بيانات المنبه الشغال حالياً (العنوان ومسار الصوت)
  Future<void> _fetchRingingAlarmData() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // استخراج الـ ID الخاص بالمنبه اللي رن دلوقتي
    final id = widget.notificationId ?? _extractAlarmId();
    
    if (id != null) {
      final alarm = await Alarm.getAlarm(id);
      if (alarm != null) {
        // ضبط التايمر على مدة هذا الصوت بالظبط
        _setupDynamicCloseTimer(
          alarm.assetAudioPath ?? 'assets/sounds/adhan.mp3',
        );

        if (mounted && (prayerTitle == null || prayerTitle!.isEmpty)) {
          setState(() {
            prayerTitle = alarm.notificationSettings.title;
          });
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

    return PopScope(
      canPop: false, // 👈 يمنع الرجوع العادي للـ Home
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeScreen(); // 👈 ينفذ نفس أمر زرار الإيقاف ويقفل التطبيق بالكامل
      },
      child: Scaffold(
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
    ),
    );
  }
}
