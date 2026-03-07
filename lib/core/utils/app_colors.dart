import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlack = Color(0xFF1E1E1E);
  static const Color secondaryGold = Color(0xFFD4AF37);
  static const Color lightGold = Color.fromARGB(255, 255, 220, 107);
  static const Color silverMarble = Color(0xFFE0E0E0);
  static const Color deepBackground = Color(0xFF121212);
  static const Color amoledBackground = Color(0xFF000000);
  static const Color lightBackground = Color(0xFFF5F5F5);
  static const Color darkText = Color(0xFF121212);
  static const Color lightText = Color(0xFFFFFFFF);
  static const Color errorColor = Color(0xFFCF4647);
  static const Color warningColor = Color(0xFFD68F1F);
  static const Color successColor = Color(0xFF2D9C5E);
  static const Gradient goldenGradient = LinearGradient(
    colors: [Color(0xFFD4AF37), Color(0xFFFFD700), Color(0xFFD4AF37)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
