import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_icon.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:lottie/lottie.dart';

class QiblaScreen extends StatelessWidget {
  const QiblaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GradientText(
          'القبلة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.amber),
            onPressed: () =>
                _showCalibrationDialog(context), // الدالة اللي هتفتح الـ Dialog
          ),
        ],
        centerTitle: true,
      ),
      body: FutureBuilder(
        // 1. فحص دعم مستشعر البوصلة في الموبايل
        future: FlutterQiblah.androidDeviceSensorSupport(),
        builder: (context, AsyncSnapshot<bool?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            );
          }
          if (snapshot.hasError || (snapshot.data == false)) {
            // return Center(
            //   child: Text(
            //     'عذراً، جهازك لا يدعم مستشعر البوصلة 🧭',
            //     style: GoogleFonts.cairo(
            //       color: AppColors.silverMarble,
            //       fontSize: 18,
            //       fontWeight: FontWeight.bold,
            //     ),
            //   ),
            // );
            return const _QiblaCompassWidget(); //only for testing on desktop, remove this when testing on mobile devices without compass support.
          }

          // لو الجهاز مدعوم، نعرض البوصلة الحية
          return const _QiblaCompassWidget();
        },
      ),
    );
  }
}

class _QiblaCompassWidget extends StatelessWidget {
  const _QiblaCompassWidget();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      // 2. الاستماع لتحديثات الاتجاه لحظة بلحظة
      stream: FlutterQiblah.qiblahStream,
      builder: (_, AsyncSnapshot<QiblahDirection> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.amber),
          );
        }

        final qiblahDirection = snapshot.data;
        if (qiblahDirection == null) return const SizedBox();

        // 3. حساب زاوية الدوران وتحويلها لراديان (نضرب في -1 عشان تلف صح)
        final compassAngle = (qiblahDirection.qiblah * (pi / 180) * -1);

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 1,
                child: Text(
                  'قم بتدوير الهاتف حتى يتطابق السهم مع القبلة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: AppColors.silverMarble,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 50),

              // 👈 سحر الدوران بيحصل هنا
              Expanded(
                flex: 4,
                child: Transform.rotate(
                  angle: compassAngle,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // إطار البوصلة الخارجي
                      Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.silverMarble.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: const Center(
                          // أيقونة خلفية خفيفة
                          child: Icon(
                            Icons.explore_outlined,
                            size: 270,
                            color: Colors.white12,
                          ),
                        ),
                      ),
                      // سهم القبلة (باستخدام الـ GradientIcon بتاعك)
                      Transform.translate(
                        offset: const Offset(0, -100), // رفع السهم لفوق شوية
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const GradientIcon(
                              icon: Icons.navigation,
                              size: 90,
                            ),
                            Image.asset(
                              'assets/icons/kaaba_haram.png',
                              width: 30,
                              height: 30,
                              color: AppColors.deepBackground,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 50),
              // عرض الزاوية بالدرجات
              Expanded(
                child: GradientText(
                  '${qiblahDirection.direction.toInt()}°',
                  style: GoogleFonts.cairo(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Text(
                  'ضع الهاتف بشكل مسطح للحصول على أدق نتيجة',
                  style: GoogleFonts.cairo(
                    color: AppColors.silverMarble.withOpacity(0.7),
                    fontSize: 14,
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

void _showCalibrationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        // خلفية داكنة تليق مع التطبيق
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.amber.withOpacity(0.3), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.screen_rotation, color: Colors.amber),
            const SizedBox(width: 10),
            GradientText(
              'معايرة البوصلة',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إذا كانت البوصلة غير دقيقة أو متوقفة، يُرجى اتباع الخطوات التالية:',
              style: GoogleFonts.cairo(
                color: AppColors.silverMarble,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            _buildInstructionRow('1', 'ابتعد عن أي أجهزة إلكترونية أو معادن.'),
            const SizedBox(height: 12),
            _buildInstructionRow(
              '2',
              'حرك الهاتف في الهواء على شكل رقم 8 (∞) عدة مرات.',
            ),
            const SizedBox(height: 12),
            Center(
              child: Lottie.asset(
                'assets/animations/device calibration.json',
                width: 150,
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            _buildInstructionRow('3', 'ضع الهاتف بشكل مسطح (أفقي) مرة أخرى.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'حسناً، فهمت',
              style: GoogleFonts.cairo(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      );
    },
  );
}

// ويدجت مساعدة عشان نرسم الخطوات بشكل مرتب وشيك
Widget _buildInstructionRow(String number, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            text,
            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 15),
          ),
        ),
      ),
    ],
  );
}
