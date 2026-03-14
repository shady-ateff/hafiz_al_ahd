import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class AppTheme {
  // ─────────────── DARK THEME ───────────────
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(AppColors.primaryBlack),
          foregroundColor: WidgetStateProperty.all(AppColors.secondaryGold),
          shape: WidgetStateProperty.all(
            const CircleBorder(
              side: BorderSide(color: AppColors.secondaryGold, width: .3),
            ),
          ),
        ),
      ),
      primaryColor: AppColors.primaryBlack,
      scaffoldBackgroundColor: AppColors.amoledBackground,
      cardColor: AppColors.primaryBlack,
      hintColor: AppColors.silverMarble,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.secondaryGold,
        secondary: AppColors.lightGold,
        onPrimary: AppColors.primaryBlack,
        onSecondary: AppColors.primaryBlack,
        surface: AppColors.primaryBlack,
        onSurface: AppColors.silverMarble,
      ),
      iconTheme: const IconThemeData(color: AppColors.silverMarble),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.amoledBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.silverMarble),
        titleTextStyle: TextStyle(
          color: AppColors.silverMarble,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: TextTheme(
        titleLarge: const TextStyle(
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
        ),
        displayLarge: const TextStyle(
          fontFamily: 'Thuluth',
          fontSize: 45,
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
        bodyLarge: GoogleFonts.amiri(
          fontSize: 20,
          color: AppColors.silverMarble,
          fontWeight: FontWeight.bold,
        ),
        bodyMedium: GoogleFonts.cairo(
          fontSize: 14,
          color: AppColors.silverMarble,
        ),
      ),
      dividerColor: AppColors.primaryBlack,
      buttonTheme: ButtonThemeData(
        buttonColor: AppColors.secondaryGold,
        textTheme: ButtonTextTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    );
  }

  // ─────────────── LIGHT THEME (same gold palette) ───────────────
  // Background: warm off-white  |  Surfaces: white  |  Gold accents preserved
  static const Color _lightBackground = Color(0xFFF7F3EC); // warm cream
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightCardBg = Color(0xFFFFF8EC); // very light gold tint
  static const Color _lightText = Color(0xFF1A1208); // almost black warm
  static const Color _lightSubtext = Color(0xFF7A6840); // warm brown-gold

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.secondaryGold,
      scaffoldBackgroundColor: _lightBackground,
      cardColor: _lightCardBg,
      hintColor: _lightSubtext,
      colorScheme: const ColorScheme.light(
        primary: AppColors.secondaryGold,
        secondary: AppColors.lightGold,
        onPrimary: _lightText,
        onSecondary: _lightText,
        surface: _lightSurface,
        onSurface: _lightText,
      ),
      iconTheme: const IconThemeData(color: AppColors.secondaryGold),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(_lightSurface),
          foregroundColor: WidgetStateProperty.all(AppColors.secondaryGold),
          shape: WidgetStateProperty.all(
            const CircleBorder(
              side: BorderSide(color: AppColors.secondaryGold, width: .3),
            ),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.secondaryGold),
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: TextTheme(
        titleLarge: const TextStyle(
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
        ),
        displayLarge: const TextStyle(
          fontFamily: 'Thuluth',
          fontSize: 45,
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
        bodyLarge: GoogleFonts.amiri(
          fontSize: 20,
          color: _lightText,
          fontWeight: FontWeight.bold,
        ),
        bodyMedium: GoogleFonts.cairo(fontSize: 14, color: _lightSubtext),
      ),
      dividerColor: const Color(0xFFE8D9B5),
      listTileTheme: const ListTileThemeData(
        tileColor: _lightCardBg,
        textColor: _lightText,
        iconColor: AppColors.secondaryGold,
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: AppColors.secondaryGold,
        textTheme: ButtonTextTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    );
  }
}
