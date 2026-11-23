import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class AppTheme {
  // ─────────────── DARK THEME ───────────────
  static ThemeData get darkTheme {
    return ThemeData(
      dividerTheme: DividerThemeData(color: AppColors.deepBackground),
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
      timePickerTheme: _buildTimePickerTheme(isDark: true),
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
      timePickerTheme: _buildTimePickerTheme(isDark: false),
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

  // ─────────────── TIME PICKER THEME ───────────────
  static TimePickerThemeData _buildTimePickerTheme({required bool isDark}) {
    return TimePickerThemeData(
      backgroundColor: isDark ? AppColors.primaryBlack : const Color(0xFFFFFDF8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: AppColors.secondaryGold.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      elevation: 8,
      dialBackgroundColor:
          isDark ? const Color(0xFF141414) : const Color(0xFFF9F5EC),
      dialHandColor: AppColors.secondaryGold,
      dialTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return isDark ? AppColors.silverMarble : _lightText;
      }),
      dialTextStyle: GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
      hourMinuteColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.secondaryGold.withValues(alpha: isDark ? 0.25 : 0.18);
        }
        return isDark ? const Color(0xFF262626) : const Color(0xFFF0EDE5);
      }),
      hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark ? AppColors.lightGold : AppColors.secondaryGold;
        }
        return isDark ? Colors.white70 : _lightText;
      }),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.secondaryGold.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      hourMinuteTextStyle: GoogleFonts.cairo(
        fontSize: 42,
        fontWeight: FontWeight.bold,
      ),
      dayPeriodColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.secondaryGold;
        }
        return isDark ? const Color(0xFF262626) : const Color(0xFFF0EDE5);
      }),
      dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return isDark ? Colors.white60 : _lightText;
      }),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.secondaryGold.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      dayPeriodTextStyle: GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
      dayPeriodBorderSide: BorderSide(
        color: AppColors.secondaryGold.withValues(alpha: 0.4),
        width: 1.0,
      ),
      helpTextStyle: GoogleFonts.cairo(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryGold,
      ),
      entryModeIconColor: AppColors.secondaryGold,
      confirmButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.secondaryGold),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        elevation: WidgetStateProperty.all(2),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cancelButtonStyle: ButtonStyle(
        foregroundColor:
            WidgetStateProperty.all(isDark ? Colors.white70 : _lightSubtext),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        textStyle: WidgetStateProperty.all(
          GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
