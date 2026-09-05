import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/DI/service_locator.dart';
import '../widgets/quran_page_widget.dart';
import '../../data/datasources/surah_names.dart';

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  late PageController _pageController;
  int _currentPage = 1; // المصحف يبدأ من صفحة 1
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _loadLastPage();
  }

  Future<void> _loadLastPage() async {
    final prefs = sl<SharedPreferences>();
    final lastPage = prefs.getInt('last_quran_page') ?? 1;
    setState(() {
      _currentPage = lastPage;
      _pageController = PageController(initialPage: _currentPage - 1);
      _isInit = true;
    });
    context.read<QuranCubit>().loadPage(_currentPage);
  }

  Future<void> _saveLastPage(int page) async {
    final prefs = sl<SharedPreferences>();
    await prefs.setInt('last_quran_page', page);
  }

  @override
  void dispose() {
    if (_isInit) _pageController.dispose();
    super.dispose();
  }

  double _sliderValue = 1.0;
  bool _isSliding = false;

  int _getCurrentSurah(int page) {
    for (int i = 113; i >= 0; i--) {
      if (page >= surahStartPages[i]) {
        return i + 1;
      }
    }
    return 1;
  }

  String _getQcfSurahName(int surahNumber) {
    if (64396 + surahNumber >= 64434) {
      return String.fromCharCode(64429 + surahNumber);
    } else {
      return String.fromCharCode(64396 + surahNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Scaffold(
        backgroundColor: Color(0xffFFFCE6),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isSliding) {
      _sliderValue = _getCurrentSurah(_currentPage).toDouble();
    }

    return Scaffold(
      backgroundColor: const Color(0xffFFFCE6),

      body: Column(
        children: [
          Container(
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
                      foregroundColor: AppColors.darkSilverMarble,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    'المصحف الشريف',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.darkSilverMarble,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: 604,
                  reverse:
                      false, // تم تعديلها لتتوافق مع اتجاه التمرير العربي السليم
                  onPageChanged: (index) {
                    final int pageNumber = index + 1;
                    setState(() {
                      _currentPage = pageNumber;
                    });
                    context.read<QuranCubit>().loadPage(pageNumber);
                    _saveLastPage(pageNumber);

                    if (pageNumber < 604) {
                      context.read<QuranCubit>().loadPage(pageNumber + 1);
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
                        if (state is QuranLoading || state is QuranInitial) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (state is QuranError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  state.message,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                ElevatedButton(
                                  onPressed: () => context
                                      .read<QuranCubit>()
                                      .loadPage(pageNumber),
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          );
                        } else if (state is QuranPageLoaded &&
                            state.page.pageNumber == pageNumber) {
                          return QuranPageWidget(
                            page: state.page,
                            isFontLoaded: state.isFontLoaded,
                          );
                        }
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.deepBackground,
                          ),
                        );
                      },
                    );
                  },
                ),

                // سلايدر السور في الأسفل
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        valueIndicatorTextStyle: const TextStyle(
                          fontFamily: 'QCF_BSML',
                          fontSize: 28,
                          color: Colors.white,
                        ),
                        showValueIndicator: ShowValueIndicator.always,
                        thumbColor: const Color(0xffD4AF37),
                        activeTrackColor: const Color(0xffD4AF37),
                        inactiveTrackColor: Colors.black26,
                        valueIndicatorColor: Colors.black87,
                      ),
                      child: Slider(
                        value: _sliderValue,
                        min: 1,
                        max: 114,
                        divisions: 113,
                        label:
                            "${String.fromCharCode(64396)} ${_getQcfSurahName(_sliderValue.toInt())}",
                        onChanged: (val) {
                          setState(() {
                            _sliderValue = val;
                            _isSliding = true;
                          });
                        },
                        onChangeEnd: (val) {
                          final targetPage = surahStartPages[val.toInt() - 1];
                          _pageController.jumpToPage(targetPage - 1);
                          setState(() {
                            _isSliding = false;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
