import 'package:flutter/material.dart';
import '../../../../core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';

/// Pure presentation BottomSheet widget displaying Ayah details and placeholder action buttons.
/// It contains no repository access, no service locator dependencies, and interacts only
/// through constructor parameters and callbacks.
class QuranAyahActionBottomSheet extends StatelessWidget {
  final QuranAyah ayah;
  final bool isBookmarked;
  final Color? bookmarkColor;
  final VoidCallback? onTafseerTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onShareTap;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onCloseTap;

  const QuranAyahActionBottomSheet({
    super.key,
    required this.ayah,
    this.isBookmarked = false,
    this.bookmarkColor,
    this.onTafseerTap,
    this.onCopyTap,
    this.onShareTap,
    this.onBookmarkTap,
    this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final initialSize = isLandscape ? 0.60 : 0.50;
    final minSize = isLandscape ? 0.30: 0.30;
    const maxSize = 0.80;
    final snapSizes = isLandscape
        ? const [0.60, 0.80]
        : const [0.38, 0.60, 0.80];

    final sheetBgColor = isDark
        ? AppColors.primaryBlack
        : Theme.of(context).scaffoldBackgroundColor;
    final cardBgColor = isDark
        ? const Color(0xFF262626)
        : AppColors.secondaryGold.withValues(alpha: 0.05);
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.3);
    final textColor = isDark ? Colors.white : AppColors.darkText;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: DraggableScrollableSheet(
            initialChildSize: initialSize,
            minChildSize: minSize,
            maxChildSize: maxSize,
            snap: true,
            snapSizes: snapSizes,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: sheetBgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 1. Drag Handle
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Header: Surah Name • Ayah Number • Page Number
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${getSurahName(ayah.id.surahNumber)} • الآية ${ayah.id.ayahNumber} • صفحة ${ayah.pageNumber}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Tajawal',
                                    color: AppColors.secondaryGold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${ayah.wordsCount} كلمات',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Tajawal',
                                    color: subtextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: subtextColor,
                            tooltip: 'إغلاق',
                            onPressed:
                                onCloseTap ??
                                () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),

                    // 3. Scrollable Uthmani Text Card
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              ayah.uthmaniText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 20,
                                height: 1.8,
                                color: textColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. Action Buttons (UI Placeholders)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            context: context,
                            icon: Icons.auto_stories_outlined,
                            label: 'التفسير',
                            onTap: onTafseerTap,
                          ),
                          _buildActionButton(
                            context: context,
                            icon: Icons.copy_rounded,
                            label: 'نسخ',
                            onTap: onCopyTap,
                          ),
                          _buildActionButton(
                            context: context,
                            icon: Icons.share_rounded,
                            label: 'مشاركة',
                            onTap: onShareTap,
                          ),
                          _buildActionButton(
                            context: context,
                            icon: isBookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: 'فاصلة',
                            onTap: onBookmarkTap,
                            isActive: isBookmarked,
                            activeColor: bookmarkColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    final effectiveColor = activeColor ?? AppColors.secondaryGold;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemColor = isActive
        ? effectiveColor
        : (isDark ? Colors.white : AppColors.darkText);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? effectiveColor.withValues(alpha: 0.28)
                    : AppColors.secondaryGold.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: itemColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
