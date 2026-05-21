import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_icon.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:lottie/lottie.dart';

// 👈 1. حولناها لـ StatefulWidget عشان نحافظ على الـ Future
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}
class _QiblaScreenState extends State<QiblaScreen> {
  // شلنا الـ static عشان نعطي البلوجن وقت (Async Gap) يعمل Reset للسنسور
  // لو دخلنا وخرجنا بسرعة، الـ FlutterQiblah بيعلق لو معملناش await
  Future<bool?>? _deviceSupportFuture;

  @override
  void initState() {
    super.initState();
    _deviceSupportFuture = FlutterQiblah.androidDeviceSensorSupport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBg,
      appBar: AppBar(
        title: GradientText(
          'القبلة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.amber),
            onPressed: () => _showCalibrationDialog(context),
          ),
        ],
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: _deviceSupportFuture,
        builder: (context, AsyncSnapshot<bool?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }
          if (snapshot.hasError || (snapshot.data == false)) {
            // ... (نفس كود الإيرور بتاعك بالظبط مفيش تغيير)
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
                  const SizedBox(height: 20),
                  Text(
                    'عذراً، جهازك لا يدعم مستشعر البوصلة.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(color: context.primaryText, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return const _QiblaCompassWidget();
        },
      ),
    );
  }
}

class _QiblaCompassWidget extends StatefulWidget {
  const _QiblaCompassWidget();

  @override
  State<_QiblaCompassWidget> createState() => _QiblaCompassWidgetState();
}

class _QiblaCompassWidgetState extends State<_QiblaCompassWidget> {
  static QiblahDirection? _lastDirection;
  Stream<QiblahDirection>? _qiblahStream;

  @override
  void initState() {
    super.initState();
    // تأخير 300 ملي ثانية لعلاج الـ Race Condition في قناة الـ Native
    // بحيث نعطي النظام وقت يقفل البوصلة القديمة قبل ما يفتح الجديدة لو اليوزر فتح الشاشة وقفلها بسرعة
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _qiblahStream = FlutterQiblah.qiblahStream;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_qiblahStream == null) {
      if (_lastDirection != null) {
        return _buildUI(context, _lastDirection!);
      }
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }

    return StreamBuilder<QiblahDirection>(
      stream: _qiblahStream,
      builder: (_, AsyncSnapshot<QiblahDirection> snapshot) {
        if (snapshot.hasData) {
          _lastDirection = snapshot.data;
        }

        final qiblahDirection = snapshot.data ?? _lastDirection;
        
        if (qiblahDirection == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }

        return _buildUI(context, qiblahDirection);
      },
    );
  }

  Widget _buildUI(BuildContext context, QiblahDirection qiblahDirection) {
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
              style: GoogleFonts.cairo(color: context.secondaryText, fontSize: 16),
            ),
          ),
          const SizedBox(height: 50),
          Expanded(
            flex: 4,
            child: Transform.rotate(
              angle: compassAngle,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: context.borderGold, width: 2),
                    ),
                    child: Center(
                      child: Icon(Icons.explore_outlined, size: 270, color: context.divider),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -100),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const GradientIcon(icon: Icons.navigation, size: 90),
                        Image.asset(
                          'assets/icons/kaaba_haram.png',
                          width: 30,
                          height: 30,
                          color: context.cardBg,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 50),
          Expanded(
            child: GradientText(
              '${qiblahDirection.direction.toInt()}°',
              style: GoogleFonts.cairo(fontSize: 48, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Text(
              'ضع الهاتف بشكل مسطح للحصول على أدق نتيجة',
              style: GoogleFonts.cairo(
                color: context.secondaryText.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ... دالة _showCalibrationDialog ودالة _buildInstructionRow زي ما هما مفيش فيهم تغيير
void _showCalibrationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: context.surfaceBg, // 👈 خلفية الديالوج بقت دايناميك
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
                color: context.secondaryText, // 👈 لون دايناميك
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            _buildInstructionRow(
              context,
              '1',
              'ابتعد عن أي أجهزة إلكترونية أو معادن.',
            ),
            const SizedBox(height: 12),
            _buildInstructionRow(
              context,
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
            _buildInstructionRow(
              context,
              '3',
              'ضع الهاتف بشكل مسطح (أفقي) مرة أخرى.',
            ),
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

// 👈 بصينا الـ context عشان نقدر نقرأ الألوان الدايناميك
Widget _buildInstructionRow(BuildContext context, String number, String text) {
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
            style: GoogleFonts.cairo(
              color: context.primaryText,
              fontSize: 15,
            ), // 👈 لون دايناميك
          ),
        ),
      ),
    ],
  );
}
