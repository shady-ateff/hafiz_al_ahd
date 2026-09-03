import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/misbaha_screen.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_tracker_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/celebration_dialog.dart';

class AzkarListScreen extends StatefulWidget {
  final String categoryTitle;
  final List<AzkarItem> azkarList;

  const AzkarListScreen({
    super.key,
    required this.categoryTitle,
    required this.azkarList,
  });

  @override
  State<AzkarListScreen> createState() => _AzkarListScreenState();
}

class _AzkarListScreenState extends State<AzkarListScreen> {
  bool _isCategoryCompleted = false;

  @override
  void dispose() {
    // Reset non-daily categories when leaving the screen
    if (widget.categoryTitle != 'أذكار الصباح' &&
        widget.categoryTitle != 'أذكار المساء') {
      context.read<AzkarTrackerCubit>().resetCategory(widget.azkarList);
    }
    super.dispose();
  }

  void _checkCategoryCompletion(int completedCount) {
    if (completedCount == widget.azkarList.length && !_isCategoryCompleted) {
      _isCategoryCompleted = true;
      context.read<GamificationCubit>().completeAzkarCategory(
        widget.categoryTitle,
      );
      showCelebrationDialog(
        context,
        onContinue: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        onReset: () {
          context.read<AzkarTrackerCubit>().resetCategory(widget.azkarList);
          setState(() {
            _isCategoryCompleted = false;
          });
          Navigator.of(context).pop(); // Close Dialog
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<AzkarTrackerCubit>();
    int completedCount = 0;
    for (var item in widget.azkarList) {
      final target = item.count > 0 ? item.count : 1;
      final current = cubit.getZikrCount(item.text);
      if (current >= target) {
        completedCount++;
      }
    }
    
    // Check completion without setState, just side effect if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkCategoryCompletion(completedCount);
    });

    final double overallProgress = widget.azkarList.isEmpty
        ? 0
        : (completedCount / widget.azkarList.length);

    return Scaffold(
      backgroundColor: context.screenBg, // 👈 دايناميك
      appBar: AppBar(
        backgroundColor: context.screenBg, // 👈 دايناميك
        elevation: 0,
        title: Column(
          children: [
            GradientText(
              widget.categoryTitle,
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.azkarList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: overallProgress,
                          backgroundColor: AppColors.secondaryGold.withOpacity(
                            0.2,
                          ),
                          color: AppColors.secondaryGold,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(overallProgress * 100).toInt()}%',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        centerTitle: true,
        toolbarHeight: widget.azkarList.isNotEmpty ? 80 : kToolbarHeight,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.primaryText, // 👈 دايناميك عشان ميبقاش أبيض ويختفي
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: widget.azkarList.isEmpty
          ? Center(
              child: Text(
                'لا توجد أذكار حالياً',
                style: GoogleFonts.cairo(
                  color: context.secondaryText,
                  fontSize: 18,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(
                top: 20,
                bottom: 200,
                left: 20,
                right: 20,
              ),
              itemCount: widget.azkarList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return AzkarItemCard(
                  item: widget.azkarList[index],
                );
              },
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    MisbahaScreen(dynamicAzkarList: widget.azkarList),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: AppColors.secondaryGold,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            overlayColor: Theme.of(context).primaryColor.withOpacity(0.1),
          ),
          child: Text(
            'الفتح في المسبحة',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.screenBg,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class AzkarItemCard extends StatefulWidget {
  final AzkarItem item;

  const AzkarItemCard({
    super.key,
    required this.item,
  });

  @override
  State<AzkarItemCard> createState() => _AzkarItemCardState();
}

class _AzkarItemCardState extends State<AzkarItemCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _fadeController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onTap(int currentCount, int targetCount) {
    if (currentCount >= targetCount) return;

    final cubit = context.read<AzkarTrackerCubit>();
    cubit.incrementZikr(widget.item);

    if (currentCount + 1 >= targetCount) {
      _fadeController.forward();
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final int targetCount = widget.item.count > 0 ? widget.item.count : 1;
    final int currentCount = context.watch<AzkarTrackerCubit>().getZikrCount(widget.item.text);
    final bool isCompleted = currentCount >= targetCount;
    final double progress = currentCount / targetCount;
    
    // Ensure animation is correct if it was completed elsewhere (like in Misbaha)
    if (isCompleted && !_fadeController.isCompleted && !_fadeController.isAnimating) {
      _fadeController.value = 1.0;
    }

    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        final double cardOpacity = (1.0 - (_fadeController.value * 0.4)).clamp(
          0.0,
          1.0,
        );

        return Opacity(
          opacity: cardOpacity,
          child: Container(
            decoration: BoxDecoration(
              color: isCompleted
                  ? context.cardBg.withOpacity(0.5)
                  : context.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCompleted
                    ? context.borderSubtle
                    : AppColors.secondaryGold.withOpacity(
                        0.2 + (progress * 0.3),
                      ),
                width: isCompleted ? 1 : 1.5,
              ),
              boxShadow: isCompleted
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.secondaryGold.withOpacity(0.05),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => _onTap(currentCount, targetCount),
                borderRadius: BorderRadius.circular(16),
                splashColor: AppColors.secondaryGold.withOpacity(0.1),
                highlightColor: AppColors.secondaryGold.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.text,
                        style: GoogleFonts.cairo(
                          color: isCompleted
                              ? context.secondaryText
                              : context.primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.item.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            widget.item.description,
                            style: GoogleFonts.cairo(
                              color: context.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          isCompleted
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.lightGold,
                                  size: 28,
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.lightGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'المرات: ${widget.item.count > 0 ? widget.item.count : 1}',
                                    style: GoogleFonts.cairo(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 4,
                                  backgroundColor: AppColors.lightGold
                                      .withOpacity(0.2),
                                  color: AppColors.secondaryGold,
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCompleted
                                        ? context.screenBg
                                        : AppColors.secondaryGold.withOpacity(
                                            0.1,
                                          ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${targetCount - currentCount}',
                                      style: GoogleFonts.cairo(
                                        color: isCompleted
                                            ? context.secondaryText
                                            : context.primaryText,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
