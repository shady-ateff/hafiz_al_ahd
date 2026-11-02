import 'package:flutter/material.dart';
import '../../../../core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';

class SurahJuzBottomSheet extends StatelessWidget {
  final Function(int) onPageSelected;

  const SurahJuzBottomSheet({super.key, required this.onPageSelected});

  String _getQcfSurahName(int surahNumber) {
    if (64396 + surahNumber >= 64434) {
      return String.fromCharCode(64429 + surahNumber);
    } else {
      return String.fromCharCode(64396 + surahNumber);
    }
  }

  static const List<String> juzNamesArabic = [
    "الأول",
    "الثاني",
    "الثالث",
    "الرابع",
    "الخامس",
    "السادس",
    "السابع",
    "الثامن",
    "التاسع",
    "العاشر",
    "الحادي عشر",
    "الثاني عشر",
    "الثالث عشر",
    "الرابع عشر",
    "الخامس عشر",
    "السادس عشر",
    "السابع عشر",
    "الثامن عشر",
    "التاسع عشر",
    "العشرون",
    "الحادي والعشرون",
    "الثاني والعشرون",
    "الثالث والعشرون",
    "الرابع والعشرون",
    "الخامس والعشرون",
    "السادس والعشرون",
    "السابع والعشرون",
    "الثامن والعشرون",
    "التاسع والعشرون",
    "الثلاثون",
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor = isDark
        ? AppColors.primaryBlack
        : Theme.of(context).scaffoldBackgroundColor;
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.3);
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;
    final unselectedTabColor = isDark ? Colors.white38 : Colors.black54;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final initialSize = isLandscape ? 0.85 : 0.65;
    final minSize = isLandscape ? 0.35 : 0.30;
    const maxSize = 0.95;
    final snapSizes = isLandscape
        ? const [0.85, 0.95]
        : const [0.65, 0.85, 0.95];

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: snapSizes,
      builder: (context, scrollController) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Container(
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
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Material(
                color: sheetBgColor,
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag Handle
                      const SizedBox(height: 12),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // TabBar
                      TabBar(
                        indicatorColor: AppColors.secondaryGold,
                        indicatorWeight: 3,
                        labelColor: AppColors.secondaryGold,
                        unselectedLabelColor: unselectedTabColor,
                        dividerColor: AppColors.deepBackground,
                        indicatorPadding: const EdgeInsets.all(5),
                        labelStyle: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        tabs: const [
                          Tab(text: "السور"),
                          Tab(text: "الأجزاء"),
                        ],
                      ),

                      // Content (TabBarView)
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Surahs List
                            ListView.separated(
                              itemCount: 114,
                              controller: scrollController,
                              physics: ClampingScrollPhysics(),
                              separatorBuilder: (context, index) => Divider(
                                color: dividerColor,
                                height: 1,
                                indent: 20,
                                endIndent: 20,
                              ),
                              itemBuilder: (context, index) {
                                final surahNumber = index + 1;
                                final page = surahStartPages[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    "${String.fromCharCode(64396)} ${_getQcfSurahName(surahNumber)}",
                                    style: TextStyle(
                                      fontFamily: 'QCF_BSML',
                                      fontSize: 32,
                                      fontWeight: FontWeight.w200,
                                      color: textColor,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.secondaryGold
                                        .withValues(alpha: 0.1),
                                    radius: 20,
                                    child: Text(
                                      "$surahNumber",
                                      style: const TextStyle(
                                        color: AppColors.secondaryGold,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Tajawal',
                                      ),
                                    ),
                                  ),
                                  trailing: Text(
                                    "صفحة $page",
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      color: unselectedTabColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  onTap: () {
                                    onPageSelected(page);
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),

                            // Juzs List
                            ListView.separated(
                              itemCount: 30,
                              separatorBuilder: (context, index) => Divider(
                                color: dividerColor,
                                height: 1,
                                indent: 20,
                                endIndent: 20,
                              ),
                              itemBuilder: (context, index) {
                                final juzNumber = index + 1;
                                final page = juzStartPages[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    "الجزء ${juzNamesArabic[index]}",
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.secondaryGold
                                        .withValues(alpha: 0.1),
                                    radius: 20,
                                    child: Text(
                                      "$juzNumber",
                                      style: const TextStyle(
                                        color: AppColors.secondaryGold,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Tajawal',
                                      ),
                                    ),
                                  ),
                                  trailing: Text(
                                    "صفحة $page",
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      color: unselectedTabColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  onTap: () {
                                    onPageSelected(page);
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
