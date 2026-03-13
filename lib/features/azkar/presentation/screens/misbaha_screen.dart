import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class ZikrItem {
  final String text;
  final int defaultTarget;

  ZikrItem(this.text, this.defaultTarget);
}

class MisbahaScreen extends StatefulWidget {
  const MisbahaScreen({super.key});

  @override
  State<MisbahaScreen> createState() => _MisbahaScreenState();
}

class _MisbahaScreenState extends State<MisbahaScreen>
    with SingleTickerProviderStateMixin {
  int _count = 0;
  int _selectedIndex = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<ZikrItem> _azkarList = [
    ZikrItem('سبحان الله', 33),
    ZikrItem('الحمد لله', 33),
    ZikrItem('الله أكبر', 33),
    ZikrItem('أستغفر الله', 100),
    ZikrItem('لا إله إلّا الله', 100),
    ZikrItem('اللهم صلِّ على محمد', 10),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150), // سرعة الضغطة
    );

    // 👈 كبرنا الـ end شوية عشان الحجم يبان وهو بيكبر (من 1.0 لـ 1.08)
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.08).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _pulseController.reverse();
          }
        });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _incrementCounter() {
    if (_count >= _azkarList[_selectedIndex].defaultTarget) {
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.lightImpact();
    // ابدأ الأنيميشن من الصفر مع كل ضغطة عشان النيون ينور فوراً
    _pulseController.forward(from: 0.0);

    setState(() {
      _count++;
      if (_count == _azkarList[_selectedIndex].defaultTarget) {
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _resetCounter() {
    HapticFeedback.mediumImpact();
    setState(() {
      _count = 0;
    });
  }

  void _changeZikr(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _count = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentZikr = _azkarList[_selectedIndex];
    final remaining = currentZikr.defaultTarget - _count;
    final progress = _count / currentZikr.defaultTarget;

    return Scaffold(
      backgroundColor: AppColors.amoledBackground,
      body: SafeArea(
        child: Column(
          children: [
            // 1. AppBar
            _buildAppBar(context),

            // 2. Tappable Zone
            Expanded(
              child: GestureDetector(
                onTap: _incrementCounter,
                behavior: HitTestBehavior.translucent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      'الذكر الحالي',
                      style: GoogleFonts.cairo(
                        color: AppColors.secondaryGold,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentZikr.text,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // 👈 3. سحر النيون بيحصل هنا بـ AnimatedBuilder
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final scale = _pulseAnimation.value;

                        // بنحسب نسبة التوهج بناءً على حجم الدايرة (من 0 لـ 1)
                        // ده هيخلي النيون يزيد وينقص بنعومة مع الحجم
                        final glowFactor = ((scale - 1.0) / 0.08).clamp(
                          0.0,
                          1.0,
                        );

                        // معادلات النيون: لما تضغط الأوباسيتي والانتشار بيزيدوا جداً
                        final currentOpacity =
                            0.15 +
                            (glowFactor * 0.65); // بتوصل لـ 0.8 وقت الضغطة
                        final currentBlur =
                            40.0 + (glowFactor * 40.0); // التمويه بيوسع
                        final currentSpread =
                            5.0 + (glowFactor * 15.0); // الانتشار بيزيد

                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 280,
                            height: 280,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.deepBackground,
                              border: Border.all(
                                color: AppColors.secondaryGold.withOpacity(
                                  0.3 + (glowFactor * 0.5),
                                ), // الإطار نفسه بينور
                                width: 2,
                              ),
                              boxShadow: [
                                // 🌟 النيون الخارجي الديناميكي
                                BoxShadow(
                                  color: AppColors.secondaryGold.withOpacity(
                                    currentOpacity.clamp(0.0, 1.0),
                                  ),
                                  blurRadius: currentBlur,
                                  spreadRadius: currentSpread,
                                ),
                                // الظل الداخلي عشان يدي عمق (3D effect)
                                const BoxShadow(
                                  color: AppColors.amoledBackground,
                                  blurRadius: 30,
                                  spreadRadius: -10,
                                  blurStyle: BlurStyle.inner,
                                ),
                              ],
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.secondaryGold.withOpacity(
                                    0.05 + (glowFactor * 0.15),
                                  ), // قلب الدايرة بينور شوية
                                  AppColors.deepBackground,
                                ],
                                radius: 0.8,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.secondaryGold
                                          .withOpacity(
                                            0.1 + (glowFactor * 0.3),
                                          ),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$_count',
                                      style: GoogleFonts.cairo(
                                        color: AppColors.lightGold,
                                        fontSize: 72,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                        shadows: [
                                          Shadow(
                                            color: AppColors.lightGold
                                                .withOpacity(
                                                  0.5 + (glowFactor * 0.5),
                                                ), // ظل الرقم نفسه بينور
                                            blurRadius: 20 + (glowFactor * 20),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'إضغط للتسبيح',
                                      style: GoogleFonts.cairo(
                                        color: AppColors.secondaryGold
                                            .withOpacity(0.8),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const Spacer(),

                    // Progress Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${currentZikr.defaultTarget}',
                                style: GoogleFonts.cairo(
                                  color: AppColors.silverMarble.withOpacity(
                                    0.6,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '$_count',
                                style: GoogleFonts.cairo(
                                  color: AppColors.silverMarble.withOpacity(
                                    0.6,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: AppColors.deepBackground,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.secondaryGold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'المتبقي: $remaining',
                            style: GoogleFonts.cairo(
                              color: AppColors.silverMarble.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Bottom Navigation Categories
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: List.generate(_azkarList.length, (index) {
                  final isSelected = index == _selectedIndex;
                  return GestureDetector(
                    onTap: () => _changeZikr(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.lightGold
                            : AppColors.deepBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.lightGold
                              : AppColors.silverMarble.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _azkarList[index].text,
                        style: GoogleFonts.cairo(
                          color: isSelected
                              ? AppColors.primaryBlack
                              : AppColors.silverMarble,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildIconBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Text(
            'المسبحة',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          _buildIconBtn(icon: Icons.refresh_rounded, onTap: _resetCounter),
        ],
      ),
    );
  }

  Widget _buildIconBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.secondaryGold.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: AppColors.lightGold, size: 20),
      ),
    );
  }
}
