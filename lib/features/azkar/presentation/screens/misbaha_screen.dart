import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart'; 
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_tracker_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/celebration_dialog.dart';

class MisbahaScreen extends StatefulWidget {
  // 👈 1. المسبحة بقت بتستقبل AzkarItem مباشرة
  final List<AzkarItem>? dynamicAzkarList; 

  const MisbahaScreen({super.key, this.dynamicAzkarList});

  @override
  State<MisbahaScreen> createState() => _MisbahaScreenState();
}

class _MisbahaScreenState extends State<MisbahaScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isTransitioning = false; 

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late ScrollController _scrollController; 

  late List<AzkarItem> _currentAzkarList;

  // 👈 2. حولنا الأذكار الافتراضية لـ AzkarItem عشان تتوافق مع الموديل بتاعك
  final List<AzkarItem> _defaultAzkarList = const [
    AzkarItem(category: 'عام', text: 'سبحان الله', description: '', reference: '', count: 33),
    AzkarItem(category: 'عام', text: 'الحمد لله', description: '', reference: '', count: 33),
    AzkarItem(category: 'عام', text: 'الله أكبر', description: '', reference: '', count: 33),
    AzkarItem(category: 'عام', text: 'أستغفر الله', description: '', reference: '', count: 100),
    AzkarItem(category: 'عام', text: 'لا إله إلّا الله', description: '', reference: '', count: 100),
    AzkarItem(category: 'عام', text: 'اللهم صلِّ على محمد', description: '', reference: '', count: 10),
  ];

  @override
  void initState() {
    super.initState();
    _currentAzkarList = (widget.dynamicAzkarList != null && widget.dynamicAzkarList!.isNotEmpty)
        ? widget.dynamicAzkarList!
        : _defaultAzkarList;

    final cubit = context.read<AzkarTrackerCubit>();
    _selectedIndex = _currentAzkarList.indexWhere((item) {
      final target = item.count > 0 ? item.count : 1;
      final current = cubit.getZikrCount(item.text);
      return current < target;
    });
    if (_selectedIndex == -1) _selectedIndex = 0; // All completed, start from 0

    _scrollController = ScrollController(
      initialScrollOffset: _selectedIndex * 110.0,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
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
    _scrollController.dispose();
    super.dispose();
  }

  void _incrementCounter() async {
    if (_isTransitioning) return; 

    final cubit = context.read<AzkarTrackerCubit>();
    final currentZikr = _currentAzkarList[_selectedIndex];
    final target = currentZikr.count > 0 ? currentZikr.count : 1;
    final int _count = cubit.getZikrCount(currentZikr.text);

    if (_count >= target) {
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.lightImpact();
    _pulseController.forward(from: 0.0);
    context.read<GamificationCubit>().incrementMisbaha();

    cubit.incrementZikr(currentZikr);
    final int newCount = cubit.getZikrCount(currentZikr.text);

    if (newCount >= target) {
      HapticFeedback.heavyImpact();

      if (_selectedIndex < _currentAzkarList.length - 1) {
        _isTransitioning = true; 
        
        await Future.delayed(const Duration(milliseconds: 600));

        if (mounted) {
          _changeZikr(_selectedIndex + 1, auto: true);
          _isTransitioning = false; 
        }
      } else {
        showCelebrationDialog(
          context,
          onContinue: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onReset: () {
            context.read<AzkarTrackerCubit>().resetCategory(_currentAzkarList);
            Navigator.of(context).pop(); // Close Dialog
            _changeZikr(0, auto: true); // Start over from the first Zikr
          },
        );
      }
    }
  }

  void _resetCounter() {
    HapticFeedback.mediumImpact();
    final currentZikr = _currentAzkarList[_selectedIndex];
    context.read<AzkarTrackerCubit>().resetZikr(currentZikr.text);
  }

  void _changeZikr(int index, {bool auto = false}) {
    if (!auto) HapticFeedback.selectionClick();
    
    setState(() {
      _selectedIndex = index;
    });

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        index * 110.0, 
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentZikr = _currentAzkarList[_selectedIndex];
    final int _count = context.watch<AzkarTrackerCubit>().getZikrCount(currentZikr.text);
    final target = currentZikr.count > 0 ? currentZikr.count : 1;
    final remaining = target - _count;
    final progress = _count / target;

    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: context.screenBg,
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final availableWidth = constraints.maxWidth;

                    final double calculatedSize = math.min(
                      availableWidth * 0.75,
                      availableHeight * 0.55,
                    );
                    final double outerCircleSize = calculatedSize.clamp(140.0, 350.0);
                    final double innerCircleSize = outerCircleSize - 20.0;
                    final double counterFontSize = outerCircleSize * 0.25;

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: availableHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'الذكر الحالي',
                                  style: GoogleFonts.cairo(
                                    color: AppColors.secondaryGold,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                  child:AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    transitionBuilder: (child, animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0.0, 0.2), 
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      );
                                    },
                                    // 👈 التعديل هنا: شيلنا الـ FittedBox وسمحنا بتعدد السطور
                                    child: Text(
                                      currentZikr.text,
                                      key: ValueKey<int>(_selectedIndex), 
                                      style: GoogleFonts.cairo(
                                        color: context.primaryText,
                                        // 👈 حجم خط ذكي: لو النص أطول من 50 حرف يصغر الخط شوية عشان يتقري براحته
                                        fontSize: currentZikr.text.length > 50 ? 18 : 32,
                                        fontWeight: FontWeight.bold,
                                        height: 1.5, // 👈 مسافة مريحة بين السطور
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),),
                              ],
                            ),

                            // Central Tappable Zone (Pulse Circle)
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                final scale = _pulseAnimation.value;
                                final glowFactor = ((scale - 1.0) / 0.08).clamp(0.0, 1.0);
                                final currentOpacity = 0.15 + (glowFactor * 0.65);
                                final currentBlur = 40.0 + (glowFactor * 40.0);
                                final currentSpread = 5.0 + (glowFactor * 15.0);

                                return Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: outerCircleSize,
                                    height: outerCircleSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: context.cardBg,
                                      border: Border.all(
                                        color: AppColors.secondaryGold.withOpacity(
                                          0.3 + (glowFactor * 0.5),
                                        ),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.secondaryGold.withOpacity(
                                            currentOpacity.clamp(0.0, 1.0),
                                          ),
                                          blurRadius: currentBlur,
                                          spreadRadius: currentSpread,
                                        ),
                                        BoxShadow(
                                          color: context.screenBg,
                                          blurRadius: 30,
                                          spreadRadius: -10,
                                          blurStyle: BlurStyle.inner,
                                        ),
                                      ],
                                      gradient: RadialGradient(
                                        colors: [
                                          AppColors.secondaryGold.withOpacity(
                                            0.05 + (glowFactor * 0.15),
                                          ),
                                          context.cardBg,
                                        ],
                                        radius: 0.8,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: innerCircleSize,
                                          height: innerCircleSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.secondaryGold.withOpacity(
                                                0.1 + (glowFactor * 0.3),
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '$_count',
                                                style: GoogleFonts.cairo(
                                                  color: AppColors.lightGold,
                                                  fontSize: counterFontSize,
                                                  fontWeight: FontWeight.bold,
                                                  height: 1.1,
                                                  shadows: [
                                                    Shadow(
                                                      color: AppColors.lightGold.withOpacity(
                                                        0.5 + (glowFactor * 0.5),
                                                      ),
                                                      blurRadius: 20 + (glowFactor * 20),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Text(
                                              'إضغط للتسبيح',
                                              style: GoogleFonts.cairo(
                                                color: AppColors.secondaryGold.withOpacity(0.8),
                                                fontSize: outerCircleSize * 0.055,
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

                            // Progress Section
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${currentZikr.count}', // 👈 التعديل هنا
                                        style: GoogleFonts.cairo(
                                          color: context.secondaryText,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        '$_count',
                                        style: GoogleFonts.cairo(
                                          color: context.secondaryText,
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
                                      backgroundColor: context.cardBg,
                                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondaryGold),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'المتبقي: $remaining',
                                    style: GoogleFonts.cairo(
                                      color: context.secondaryText,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Bottom Navigation Categories
            SizedBox(
              height: 45, 
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _currentAzkarList.length,
                itemBuilder: (context, index) {
                  final isSelected = index == _selectedIndex;
                  
                  final fullText = _currentAzkarList[index].text.trim();
                  final words = fullText.split(RegExp(r'\s+'));
                  final String shortText = words.length > 2 
                      ? '${words[0]} ${words[1]}..' 
                      : fullText;

                  return GestureDetector(
                    onTap: () => _changeZikr(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.lightGold.withOpacity(0.9) : context.cardBg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected ? AppColors.lightGold : context.borderSubtle.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        shortText,
                        style: GoogleFonts.cairo(
                          color: isSelected ? AppColors.primaryBlack : context.secondaryText,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
      child: Row(
        children: [
          _buildIconBtn(
            context: context,
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'المسبحة',
                  style: GoogleFonts.cairo(
                    color: context.primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          _buildIconBtn(
            context: context,
            icon: Icons.refresh_rounded,
            onTap: _resetCounter,
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
  }) {
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
        child: Icon(icon, color: context.primaryText, size: 20),
      ),
    );
  }
}