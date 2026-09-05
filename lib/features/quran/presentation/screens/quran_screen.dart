import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/DI/service_locator.dart';
import '../widgets/quran_page_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Scaffold(
        backgroundColor: Color(0xffFFFCE6),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xffFFFCE6),
      appBar: AppBar(
        title: const Text(
          'المصحف الشريف',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.amoledBackground,
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: 604,
        reverse: true, // من اليمين لليسار
        onPageChanged: (index) {
          final int pageNumber = index + 1;
          setState(() {
            _currentPage = pageNumber;
          });
          context.read<QuranCubit>().loadPage(pageNumber);
          _saveLastPage(pageNumber); // 👈 حفظ الصفحة الحالية

          // Pre-fetch the next page for smooth scrolling
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
                log('pageNumber ${state.runtimeType}');
                return const Center(child: CircularProgressIndicator());
              } else if (state is QuranError) {
                log('pageNumber ${state.runtimeType}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        state.message,
                        style: const TextStyle(color: Colors.red),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            context.read<QuranCubit>().loadPage(pageNumber),
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
              } else {
                log('pageNumber ${state.runtimeType}');
              }
              return Center(
                child: Text(
                  'جاري التحميل ${state.runtimeType}',
                  style: TextStyle(color: AppColors.deepBackground),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
