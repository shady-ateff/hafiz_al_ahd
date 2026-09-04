import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // 👈 استدعاء الـ Bloc
import 'package:google_fonts/google_fonts.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart'; // 👈 استدعاء الـ ThemeCubit
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';
import 'package:hafiz_al_ahd/features/qibla/presentation/screens/qibla_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/azkar_screen.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/settings_screen.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_state.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/widgets/achievement_dialog.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialTab;
  final String? initialAzkarCategory;
  const MainScreen({super.key, this.initialTab = 0, this.initialAzkarCategory});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late int _currentIndex;

  // 👈 1. تعريف الـ PageController
  late PageController _pageController;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    
    _screens = [
      const HomeScreen(),
      const QuranScreen(), // 👈 شاشة المصحف كـ Tab ثاني
      const QiblaScreen(),
      AzkarScreen(initialCategory: widget.initialAzkarCategory),
      const SettingsScreen(),
    ];
    // 👈 2. تهيئة الـ Controller وإعطاؤه الصفحة الافتراضية
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 👈 3. تنظيف الـ الميموري لما نخرج من الشاشة
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 👈 دالة عشان نغير اتجاه الشاشة حسب إحنا في أنهي صفحة
  void _updateOrientation(int index) {
    if (index == 0) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // اليوزر فتح التطبيق أو رجعله من الخلفية!
      // اضرب الـ Sticky Notification عافية فوراً
      context.read<PrayerTimesCubit>().restoreStickyNotificationIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state.isDark;
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;
    final navBarBgColor = isDark
        ? AppColors.amoledBackground
        : Theme.of(context).cardColor;
    final shadowColor = isDark
        ? AppColors.primaryBlack.withOpacity(0.5)
        : Colors.black.withOpacity(0.05);
    final unselectedIconColor = isDark
        ? AppColors.silverMarble.withAlpha(100)
        : Theme.of(context).hintColor.withOpacity(0.6);
    const activeColor = AppColors.primaryBlack;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: scaffoldBgColor,

      // 👈 4. استخدام PageView بدل استدعاء الشاشة مباشرة
      body: BlocListener<GamificationCubit, GamificationState>(
        listener: (context, state) {
          if (state is AchievementUnlockedState) {
            AchievementDialog.show(context, state.badge);
          }
        },
        child: PageView(
          controller: _pageController,
          physics:
              const BouncingScrollPhysics(), // 👈 بتدي تأثير ارتداد ناعم زي الـ iOS
          onPageChanged: (index) {
            // 👈 لما اليوزر يعمل Swipe، نحدث الـ GNav واتجاه الشاشة
            setState(() {
              _currentIndex = index;
              _updateOrientation(index);
            });
          },
          children: _screens,
        ),
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBarBgColor,
          boxShadow: [BoxShadow(blurRadius: 20, color: shadowColor)],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal:
                  15.0, // رجعنا البادينج عشان ميبقاش لازق في حافة الموبايل أوي
              vertical: 12.0,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              // 👈 1. التغليفة دي بتجبر الـ NavBar ياخد عرض الشاشة كله
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth:
                      screenWidth - 30, // خصمنا 30 بتوع البادينج اليمين والشمال
                ),
                // 👈 2. لو الشاشة صغرت أوي، دي بتسمح للـ FittedBox إنه يصغرهم بأمان
                child: IntrinsicWidth(
                  child: GNav(
                    mainAxisAlignment: MainAxisAlignment
                        .spaceBetween, // 👈 3. السر هنا: هيوزع الزراير على الأطراف بالظبط
                    rippleColor: AppColors.secondaryGold.withOpacity(0.1),
                    hoverColor: AppColors.secondaryGold.withOpacity(0.1),
                    haptic: true,
                    tabBorderRadius: 25,
                    tabBackgroundGradient: AppColors.goldenGradient,
                    tabActiveBorder: Border.all(
                      color: Colors.transparent,
                      width: 0,
                    ),
                    tabBorder: Border.all(color: Colors.transparent, width: 0),
                    tabShadow: [
                      BoxShadow(
                        color: AppColors.secondaryGold.withOpacity(0.05),
                        blurRadius: 8,
                      ),
                    ],
                    curve: Curves.easeInOut,
                    duration: const Duration(milliseconds: 300),
                    gap: 8,
                    color: unselectedIconColor,
                    activeColor: activeColor,
                    iconSize: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, // تم تقليلها لمنع الـ Overflow بعد إضافة المصحف
                      vertical: 12,
                    ),
                    textStyle: GoogleFonts.cairo(
                      color: activeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    tabs: const [
                      GButton(icon: Icons.home_filled, text: 'الرئيسية'),
                      GButton(icon: Icons.menu_book, text: 'المصحف'),
                      GButton(icon: Icons.explore, text: 'القبلة'),
                      GButton(icon: Icons.book, text: 'الأذكار'),
                      GButton(icon: Icons.settings, text: 'الإعدادات'),
                    ],
                    selectedIndex: _currentIndex,
                    onTabChange: (index) {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutQuad,
                      );
                    },
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
