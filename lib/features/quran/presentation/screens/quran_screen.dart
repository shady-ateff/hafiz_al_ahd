import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_state.dart';
import '../widgets/quran_theme_bottom_sheet.dart';
import '../../../../core/DI/service_locator.dart';
import '../widgets/quran_page_widget.dart';
import '../../data/datasources/surah_names.dart';
import '../widgets/surah_juz_bottom_sheet.dart';

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  final PageController _pageController = PageController(initialPage: 0);
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _loadLastPage();
  }

  Future<void> _loadLastPage() async {
    final prefs = sl<SharedPreferences>();
    final lastPage = prefs.getInt('last_quran_page') ?? 1;
    _currentPageNotifier.value = lastPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(lastPage - 1);
      }
      context.read<QuranCubit>().loadPage(lastPage);
      if (lastPage < 604) {
        context.read<QuranCubit>().loadPage(lastPage + 1);
      }
    });
  }

  Future<void> _saveLastPage(int pageNumber) async {
    final prefs = sl<SharedPreferences>();
    await prefs.setInt('last_quran_page', pageNumber);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  bool _isDarkMode(BuildContext context, ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranSettingsCubit, QuranSettingsState>(
      builder: (context, settingsState) {
        final isDark = _isDarkMode(context, settingsState.quranThemeMode);
        final bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xffFFFCE6);
        final headerIconColor = isDark
            ? Colors.white70
            : AppColors.darkSilverMarble;

        return Scaffold(
          backgroundColor: bgColor,
          body: Stack(
            children: [
              // 1. PageView
              GestureDetector(
                onTap: _toggleFullScreen,
                child: PageView.builder(
                  controller: _pageController,
                  reverse: false,
                  itemCount: 604,
                  onPageChanged: (index) {
                    final int pageNumber = index + 1;
                    _currentPageNotifier.value = pageNumber;
                    context.read<QuranCubit>().loadPage(pageNumber);
                    _saveLastPage(pageNumber);

                    if (pageNumber < 604) {
                      context.read<QuranCubit>().loadPage(pageNumber + 1);
                    }
                    if (pageNumber > 1) {
                      context.read<QuranCubit>().loadPage(pageNumber - 1);
                    }
                  },
                  itemBuilder: (context, index) {
                    final int pageNumber = index + 1;
                    return BlocBuilder<QuranCubit, QuranState>(
                      buildWhen: (previous, current) {
                        if (current is QuranPageLoaded) {
                          return current.page.pageNumber == pageNumber;
                        }
                        return true;
                      },
                      builder: (context, state) {
                        final cachedPage = context
                            .read<QuranCubit>()
                            .getCachedPage(pageNumber);
                        if (cachedPage != null) {
                          return QuranPageWidget(
                            page: cachedPage.page,
                            isFontLoaded: cachedPage.isFontLoaded,
                          );
                        }

                        if (state is QuranError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  state.message,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final cubit = context.read<QuranCubit>();
                                    // if it's a font error, retry initFonts
                                    if (!cubit.fontsReady) {
                                      cubit.initFonts();
                                    } else {
                                      cubit.loadPage(pageNumber);
                                    }
                                  },
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          );
                        }



                        return Center(
                          child: CircularProgressIndicator(
                            color: isDark
                                ? const Color(0xffD4AF37)
                                : AppColors.deepBackground,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // 2. Header AppBar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                top: _isFullScreen ? -150 : 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color.fromARGB(255, 90, 90, 90),
                        AppColors.primaryBlack,
                        AppColors.amoledBackground,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 70,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.arrow_back),
                            style: IconButton.styleFrom(
                              iconSize: 32,
                              foregroundColor: headerIconColor,
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          const Text(
                            'المصحف الشريف',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: AppColors.darkSilverMarble,
                            ),
                          ),
                          const Spacer(),

                          IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) {
                                  return SurahJuzBottomSheet(
                                    onPageSelected: (page) {
                                      _pageController.jumpToPage(page - 1);
                                      _currentPageNotifier.value = page;
                                    },
                                  );
                                },
                              );
                            },
                            icon: const Icon(
                              Icons.format_list_bulleted_rounded,
                            ),
                            style: IconButton.styleFrom(
                              iconSize: 32,
                              foregroundColor: const Color(
                                0xffD4AF37,
                              ), // لون ذهبي فخم
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) {
                                  return const QuranThemeBottomSheet();
                                },
                              );
                            },
                            icon: const Icon(Icons.settings),
                            style: IconButton.styleFrom(
                              iconSize: 30,
                              foregroundColor: AppColors.darkSilverMarble,
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // side: BorderSide(
                              //   color: AppColors.darkSilverMarble,
                              //   width: 1,
                              // ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Bottom Slider
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                bottom: _isFullScreen ? -150 : 30,
                left: 20,
                right: 20,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isFullScreen ? 0.0 : 1.0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (context, currentPage, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF222222).withOpacity(0.9)
                              : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$currentPage',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.deepBackground,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: const Color(0xffD4AF37),
                                  inactiveTrackColor: isDark
                                      ? Colors.grey[800]
                                      : const Color(0xffD4AF37).withOpacity(0.3),
                                  thumbColor: const Color(0xffD4AF37),
                                  trackHeight: 4.0,
                                ),
                                child: Slider(
                                  value: currentPage.toDouble(),
                                  min: 1,
                                  max: 604,
                                  onChanged: (value) {
                                    _currentPageNotifier.value = value.toInt();
                                  },
                                  onChangeEnd: (value) {
                                    _pageController.jumpToPage(value.toInt() - 1);
                                  },
                                ),
                              ),
                            ),
                            Text(
                              '604',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.deepBackground,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
