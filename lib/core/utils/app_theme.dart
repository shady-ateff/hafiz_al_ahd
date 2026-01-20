import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      primaryColor: AppColors.primaryBlack,
      scaffoldBackgroundColor: AppColors.amoledBackground,
      cardColor: AppColors.primaryBlack,
      hintColor: AppColors.silverMarble,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryBlack,
        secondary: AppColors.secondaryGold,
        onPrimary: AppColors.silverMarble,
        onSecondary: AppColors.primaryBlack,
        background: AppColors.amoledBackground,
        surface: AppColors.primaryBlack,
        onBackground: AppColors.silverMarble,
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
        // bodyLarge: TextStyle(color: AppColors.silverMarble),
        // bodyMedium: TextStyle(color: AppColors.silverMarble),
        titleLarge: TextStyle(
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
        ),
        displayLarge: TextStyle(
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
          color: AppColors.silverMarble.withOpacity(0.7),
        ),
      ),

      buttonTheme: ButtonThemeData(
        buttonColor: AppColors.secondaryGold,
        textTheme: ButtonTextTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: Colors.white,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardColor: Colors.white,
      hintColor: Colors.grey[600],
      colorScheme: const ColorScheme.light(
        primary: Colors.white,
        secondary: AppColors.secondaryGold,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        background: Color(0xFFF5F5F5),
        surface: Colors.white,
        onBackground: Colors.black,
        onSurface: Colors.black,
      ),
      iconTheme: IconThemeData(color: Colors.grey[800]),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.grey[800]),
        titleTextStyle: TextStyle(
          color: Colors.grey[800],
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.grey[800]),
        bodyMedium: TextStyle(color: Colors.grey[800]),
        titleLarge: const TextStyle(
          color: AppColors.secondaryGold,
          fontWeight: FontWeight.bold,
        ),
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: AppColors.secondaryGold,
        textTheme: ButtonTextTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    );
  }
}
