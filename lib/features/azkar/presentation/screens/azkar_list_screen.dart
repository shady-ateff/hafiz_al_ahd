import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';

class AzkarListScreen extends StatelessWidget {
  final String categoryTitle;
  final List<AzkarItem> azkarList;

  const AzkarListScreen({
    super.key,
    required this.categoryTitle,
    required this.azkarList,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.amoledBackground,
      appBar: AppBar(
        backgroundColor: AppColors.amoledBackground,
        title: GradientText(
          categoryTitle,
          style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: azkarList.isEmpty
          ? Center(
              child: Text(
                'لا توجد أذكار حالياً',
                style: GoogleFonts.cairo(
                  color: AppColors.silverMarble,
                  fontSize: 18,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              itemCount: azkarList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return AzkarItemCard(item: azkarList[index]);
              },
            ),
    );
  }
}

class AzkarItemCard extends StatefulWidget {
  final AzkarItem item;

  const AzkarItemCard({super.key, required this.item});

  @override
  State<AzkarItemCard> createState() => _AzkarItemCardState();
}

class _AzkarItemCardState extends State<AzkarItemCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late int _currentCount;
  bool _isCompleted = false;
  late AnimationController _fadeController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 👈 لو المودل جاب Count أقل من 1 بالغلط، نخليه 1 كحماية أولية
    _currentCount = widget.item.count > 0 ? widget.item.count : 1;
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

  void _onTap() {
    if (_isCompleted) return;

    setState(() {
      if (_currentCount > 1) {
        _currentCount--;
        HapticFeedback.lightImpact();
      } else {
        _currentCount = 0;
        _isCompleted = true;
        _fadeController.forward();
        HapticFeedback.heavyImpact();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 👈 الحماية من القسمة على صفر (Bulletproof Logic)
    final int safeTotalCount = widget.item.count > 0 ? widget.item.count : 1;
    final double progress = (safeTotalCount - _currentCount) / safeTotalCount;

    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        // 👈 حماية إضافية بـ clamp عشان نتأكد إن القيمة مستحيل تعدي 1.0 أو تقل عن 0.0
        final double borderOpacity = (0.2 + (progress * 0.3)).clamp(0.0, 1.0);
        final double cardOpacity = (1.0 - (_fadeController.value * 0.4)).clamp(0.0, 1.0);

        return Opacity(
          opacity: cardOpacity, 
          child: Container(
            decoration: BoxDecoration(
              color: _isCompleted
                  ? AppColors.deepBackground.withOpacity(0.5)
                  : AppColors.deepBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isCompleted
                    ? AppColors.silverMarble.withAlpha(20)
                    : AppColors.secondaryGold.withOpacity(borderOpacity), // 👈 استخدمنا القيمة الآمنة هنا
                width: _isCompleted ? 1 : 1.5,
              ),
              boxShadow: _isCompleted
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
                onTap: _onTap,
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
                          color: _isCompleted ? AppColors.silverMarble : Colors.white,
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
                              color: AppColors.silverMarble.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _isCompleted
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.lightGold,
                                  size: 28,
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.lightGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'المرات: ${widget.item.count > 0 ? widget.item.count : 1}',
                                    style: GoogleFonts.cairo(
                                      color: AppColors.lightGold,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isCompleted ? AppColors.deepBackground : AppColors.secondaryGold,
                              border: Border.all(
                                color: AppColors.lightGold.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$_currentCount',
                                style: GoogleFonts.cairo(
                                  color: _isCompleted ? AppColors.silverMarble : AppColors.primaryBlack,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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