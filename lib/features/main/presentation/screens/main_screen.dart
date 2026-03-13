import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/home/presentation/screens/home_screen.dart';
import 'package:hafiz_al_ahd/features/qibla/presentation/screens/qibla_screen.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/screens/quran_screen.dart';
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
    QuranScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBackground,
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.amoledBackground,
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              color: AppColors.primaryBlack.withOpacity(0.5),
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
              tabActiveBorder: Border.all(
                color: Colors.transparent,
                width: 0,
              ), // tab button border
              tabBorder: Border.all(
                color: Colors.transparent,
                width: 0,
              ), // unselected tab button border
              tabShadow: [
                BoxShadow(
                  color: AppColors.secondaryGold.withOpacity(0.05),
                  blurRadius: 8,
                ),
              ], // tab button shadow

              curve: Curves.easeInOut, // tab animation curves
              duration: const Duration(
                milliseconds: 300,
              ), // tab animation duration
              gap: 8, // the tab button gap between icon and text
              color: AppColors.silverMarble.withAlpha(
                100,
              ), // unselected icon color
              activeColor:
                  AppColors.primaryBlack, // selected icon and text color
              iconSize: 26, // tab button icon size
              tabBackgroundColor:
                  AppColors.secondaryGold, // selected tab background color
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ), // navigation bar padding
              textStyle: GoogleFonts.cairo(
                color: AppColors.primaryBlack,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                GButton(icon: Icons.home_filled, text: 'الرئيسية'),
                GButton(icon: Icons.explore, text: 'القبلة'),
                GButton(icon: Icons.menu_book, text: 'المصحف'),
                GButton(icon: Icons.settings, text: 'الإعدادات'),
              ],
              selectedIndex: _currentIndex,
              onTabChange: (index) {
                setState(() {
                  if (index == 1) {
                    // لو رايح لشاشة القبلة (Index 1)، اقفل الدوران بالطول بس
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]);
                  } else {
                    // لو أي شاشة تانية، افتح الدوران براحته للـ Fluid Design
                    SystemChrome.setPreferredOrientations(
                      DeviceOrientation.values,
                    );
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
