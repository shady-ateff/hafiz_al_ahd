import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

/// Extension on BuildContext to quickly get theme-aware colors
/// for the app's dual-theme (dark amoled + warm light gold palette).
extension ThemeHelper on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  // ── Backgrounds ──────────────────────────────────────────────────
  /// Main scaffold background
  Color get screenBg =>
      isDarkMode ? AppColors.amoledBackground : const Color(0xFFF7F3EC);

  /// Card / container surface
  Color get cardBg =>
      isDarkMode ? AppColors.deepBackground : const Color(0xFFFFF8EC);

  /// Slightly elevated surface (e.g. bottom bar, dialog)
  Color get surfaceBg =>
      isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────────────
  /// Primary body text
  Color get primaryText =>
      isDarkMode ? AppColors.silverMarble : const Color(0xFF1A1208);

  /// Secondary / subtitle text
  Color get secondaryText =>
      isDarkMode ? Colors.grey[400]! : const Color(0xFF7A6840);

  // ── Borders ───────────────────────────────────────────────────────
  Color get borderSubtle => isDarkMode
      ? AppColors.secondaryGold.withOpacity(0.15)
      : const Color(0xFFE8D9B5);

  Color get borderGold => isDarkMode
      ? AppColors.secondaryGold.withOpacity(0.3)
      : AppColors.secondaryGold.withOpacity(0.4);

  // ── Divider ───────────────────────────────────────────────────────
  Color get divider => isDarkMode ? Colors.white10 : const Color(0xFFE8D9B5);
}
