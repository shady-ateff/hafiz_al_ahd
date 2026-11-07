import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_icon.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:lottie/lottie.dart';

// 👈 1. حولناها لـ StatefulWidget عشان نحافظ على الـ Future
class QiblaScreen extends StatefulWidget {
  final bool isActive;
  const QiblaScreen({super.key, this.isActive = true});

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
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<bool?>(
        future: _deviceSupportFuture,
        builder: (context, AsyncSnapshot<bool?> snapshot) {
          if (snapshot.hasError || (snapshot.hasData && snapshot.data == false)) {
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

          return _QiblaCompassWidget(isActive: widget.isActive);
        },
      ),
    );
  }
}

class _QiblaCompassWidget extends StatefulWidget {
  final bool isActive;
  const _QiblaCompassWidget({this.isActive = true});

  @override
  State<_QiblaCompassWidget> createState() => _QiblaCompassWidgetState();
}

class _QiblaCompassWidgetState extends State<_QiblaCompassWidget>
    with WidgetsBindingObserver {
  static QiblahDirection? _lastDirection;
  StreamSubscription<QiblahDirection>? _subscription;
  Timer? _debounceTimer;
  int _eventCount = 0;
  bool _isAppResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _startListening();
    }
  }

  @override
  void didUpdateWidget(covariant _QiblaCompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive && _isAppResumed) {
        _startListening();
      } else {
        _stopListening();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppResumed = true;
      if (widget.isActive && _subscription == null && _debounceTimer == null) {
        _startListening();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isAppResumed = false;
      _stopListening();
    }
  }

  void _startListening() {
    if (_debounceTimer != null || _subscription != null) return;

    // تأخير 300 ملي ثانية لعلاج الـ Race Condition في قناة الـ Native
    // وتفادي تفعيل السنسور أثناء التمرير السريع بين التبويبات
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _debounceTimer = null;
      if (!mounted || !widget.isActive || !_isAppResumed) return;

      debugPrint('[HafizQibla] Subscribing to qiblahStream (isActive: true)');
      _eventCount = 0;
      _subscription = FlutterQiblah.qiblahStream.listen(
        (direction) {
          _eventCount++;
          if (_eventCount <= 3 || _eventCount % 100 == 0) {
            debugPrint(
              '[HafizQibla] Event #$_eventCount: direction=${direction.direction.toStringAsFixed(1)}°, qiblah=${direction.qiblah.toStringAsFixed(1)}°',
            );
          }
          if (mounted) {
            setState(() {
              _lastDirection = direction;
            });
          }
        },
        onError: (error) {
          debugPrint('[HafizQibla] Sensor stream error: $error');
        },
      );
    });
  }

  void _stopListening() {
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    }
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
      debugPrint(
        '[HafizQibla] Cancelled qiblahStream subscription (total events: $_eventCount)',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qiblahDirection =
        _lastDirection ?? const QiblahDirection(0, 0, 0);

    return _buildUI(context, qiblahDirection);
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
          const SizedBox(height: 30),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                GradientText(
                  '${qiblahDirection.direction.toInt()}°',
                  style: GoogleFonts.cairo(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _showCalibrationDialog(context),
                  icon: const Icon(Icons.screen_rotation_rounded, color: Colors.amber, size: 20),
                  label: Text(
                    'معايرة البوصلة',
                    style: GoogleFonts.cairo(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
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
