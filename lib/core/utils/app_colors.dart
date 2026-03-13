import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlack = Color(0xFF1E1E1E);
  static const Color secondaryGold = Color(0xFFbc8c15);
  static const Color lightGold = Color(0xFFF9D406);
  static const Color silverMarble = Color(0xFFE0E0E0);
  static const Color iqamaWarning = Color(0xFFD84315);
  static const Color darkSilverMarble = Color(0xFFc4c8ca);
  static const Color deepBackground = Color(0xFF121212);
  static const Color amoledBackground = Color(0xFF000000);
  static const Color lightBackground = Color(0xFFF5F5F5);
  static const Color darkText = Color(0xFF121212);
  static const Color lightText = Color(0xFFFFFFFF);
  static const Color errorColor = Color(0xFFCF4647);
  static const Color warningColor = Color(0xFFD68F1F);
  static const Color successColor = Color(0xFF2D9C5E);
  static const Gradient goldenGradient = LinearGradient(
    colors: [lightGold, secondaryGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static Gradient silverGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.silverMarble,
      // AppColors.secondaryGold,
      AppColors.darkSilverMarble,
      // AppColors.deepBackground,
    ],
  );
  static Gradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.iqamaWarning.withOpacity(0.7), AppColors.iqamaWarning],
  );
}
