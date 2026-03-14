import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // 👈 استدعاء الـ Bloc
import 'package:google_fonts/google_fonts.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart'; // 👈 استدعاء الـ ThemeCubit
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';
import 'package:hafiz_al_ahd/features/qibla/presentation/screens/qibla_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/azkar_screen.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    QiblaScreen(),
    AzkarScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // 👈 1. قراءة حالة الثيم الحالي
    final isDark = context.watch<ThemeCubit>().state.isDark;

    // 👈 2. تجهيز الألوان المتغيرة
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

    // اللون النشط هيفضل أسود في الحالتين لأن الخلفية بتاعته ذهبي (والأسود على الذهبي تباينه ممتاز دايماً)
    const activeColor = AppColors.primaryBlack;

    return Scaffold(
      backgroundColor: scaffoldBgColor, // 👈 التغيير هنا
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBarBgColor, // 👈 التغيير هنا
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              color: shadowColor, // 👈 التغيير هنا
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 15.0,
              vertical: 12.0,
            ),
            child: GNav(
              rippleColor: AppColors.secondaryGold.withOpacity(0.1),
              hoverColor: AppColors.secondaryGold.withOpacity(0.1),
              haptic: true, // haptic feedback
              tabBorderRadius: 25,
              tabBackgroundGradient: AppColors.goldenGradient,
              tabActiveBorder: Border.all(color: Colors.transparent, width: 0),
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
              color: unselectedIconColor, // 👈 التغيير هنا
              activeColor: activeColor,
              iconSize: 26,
              tabBackgroundColor: AppColors.secondaryGold,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: GoogleFonts.cairo(
                color: activeColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                GButton(icon: Icons.home_filled, text: 'الرئيسية'),
                GButton(icon: Icons.explore, text: 'القبلة'),
                GButton(icon: Icons.book, text: 'الأذكار'),
                GButton(icon: Icons.settings, text: 'الإعدادات'),
              ],
              selectedIndex: _currentIndex,
              onTabChange: (index) {
                setState(() {
                  if (index == 0) {
                    SystemChrome.setPreferredOrientations(
                      DeviceOrientation.values,
                    );
                  } else {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]);
                  }
                  _currentIndex = index;
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}
