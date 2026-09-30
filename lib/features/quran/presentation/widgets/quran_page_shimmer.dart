import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class QuranPageShimmer extends StatelessWidget {
  const QuranPageShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Shimmer.fromColors(
          baseColor: AppColors.secondaryGold.withValues(alpha: isDark ? 0.15 : 0.05),
          highlightColor: AppColors.secondaryGold.withValues(alpha: isDark ? 0.35 : 0.2),
          child: Column(
            children: [
              // Header Shimmer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(width: 80, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                  Container(width: 80, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                ],
              ),
              const SizedBox(height: 30),
              // Body Lines Shimmer (15 lines like standard Madani Mushaf)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(15, (index) {
                    return Container(
                      width: double.infinity,
                      height: 24,
                      margin: EdgeInsets.symmetric(horizontal: (index % 3 == 0) ? 0 : (index % 2 == 0 ? 30 : 15)), // slight stagger for organic look
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
              // Footer Shimmer
              const SizedBox(height: 30),
              Container(width: 50, height: 50, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
