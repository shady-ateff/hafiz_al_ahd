import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/quran_settings_cubit.dart';
import '../cubit/quran_settings_state.dart';

class SurahJuzBottomSheet extends StatelessWidget {
  final Function(int) onPageSelected;

  const SurahJuzBottomSheet({super.key, required this.onPageSelected});

  bool _isDarkMode(BuildContext context, ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return Theme.of(context).brightness == Brightness.dark;
  }

  String _getQcfSurahName(int surahNumber) {
    if (64396 + surahNumber >= 64434) {
      return String.fromCharCode(64429 + surahNumber);
    } else {
      return String.fromCharCode(64396 + surahNumber);
    }
  }

  final List<String> juzNamesArabic = const [
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
    return BlocBuilder<QuranSettingsCubit, QuranSettingsState>(
      builder: (context, settingsState) {
        final isDark = _isDarkMode(context, settingsState.quranThemeMode);
        final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xffFFFCE6);
        final textColor = isDark ? Colors.white70 : Colors.black87;
        final dividerColor = isDark ? Colors.white12 : Colors.black12;
        final unselectedTabColor = isDark ? Colors.white38 : Colors.black54;

        return DefaultTabController(
          length: 2,
          child: Material(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7, // 70% من الشاشة
              child: Column(
                children: [
                  // شريط السحب (Indicator)
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    height: 5,
                    width: 50,
                    decoration: BoxDecoration(
                      color: dividerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  // شريط التبويبات (TabBar)
                  TabBar(
                    indicatorColor: const Color(0xffD4AF37), // لون ذهبي فخم
                    indicatorWeight: 3,
                    labelColor: const Color(0xffD4AF37),
                    unselectedLabelColor: unselectedTabColor,
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

                  // المحتوى (TabBarView)
                  Expanded(
                    child: TabBarView(
                      children: [
                        // قائمة السور
                        ListView.separated(
                          itemCount: 114,
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
                                backgroundColor: const Color(
                                  0xffD4AF37,
                                ).withOpacity(0.1),
                                radius: 20,
                                child: Text(
                                  "$surahNumber",
                                  style: const TextStyle(
                                    color: Color(0xffD4AF37),
                                    fontWeight: FontWeight.bold,
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

                        // قائمة الأجزاء
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
                                backgroundColor: const Color(
                                  0xffD4AF37,
                                ).withOpacity(0.1),
                                radius: 20,
                                child: Text(
                                  "$juzNumber",
                                  style: const TextStyle(
                                    color: Color(0xffD4AF37),
                                    fontWeight: FontWeight.bold,
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
        );
      },
    );
  }
}
