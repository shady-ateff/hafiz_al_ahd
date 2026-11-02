import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_settings_cubit.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';

/// Renders a branded Quran Ayah share card that adapts to the user's active Mushaf theme
/// (Day / Light or Night / Dark), features the authentic Mushaf Surah header banner,
/// supports both original King Fahd Complex Mushaf fonts (QCF) and standard Uthmani (Amiri backup),
/// and wraps to fit the content height to eliminate empty negative space.
///
/// Default width: 1080 (standard high-res width).
/// Default height: null (automatically fits content height).
class QuranAyahShareCard extends StatelessWidget {
  final QuranAyah ayah;
  final double width;
  final double? height;
  final bool? isDarkMode;
  final bool? useQcf;
  final Widget? logoWidget;

  const QuranAyahShareCard({
    super.key,
    required this.ayah,
    this.width = 1080,
    this.height,
    this.isDarkMode,
    this.useQcf,
    this.logoWidget,
  });

  static String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final idx = int.tryParse(char);
      return idx != null ? digits[idx] : char;
    }).join();
  }

  static String _getQcfSurahName(int surahNumber) {
    String surahName = "";
    if (64396 + surahNumber >= 64434) {
      surahName = String.fromCharCode(64429 + surahNumber);
    } else {
      surahName = String.fromCharCode(64396 + surahNumber);
    }
    return "${String.fromCharCode(64396)} $surahName";
  }

  double _calculateFontSize(int textLength, bool isQcf) {
    if (isQcf) {
      if (textLength <= 30) return 84;
      if (textLength <= 60) return 74;
      if (textLength <= 100) return 64;
      if (textLength <= 160) return 54;
      if (textLength <= 280) return 44;
      if (textLength <= 450) return 36;
      return 30;
    } else {
      if (textLength <= 30) return 90;
      if (textLength <= 60) return 80;
      if (textLength <= 100) return 70;
      if (textLength <= 160) return 60;
      if (textLength <= 280) return 50;
      if (textLength <= 450) return 40;
      return 34;
    }
  }

  bool _resolveDarkMode(BuildContext context) {
    if (isDarkMode != null) return isDarkMode!;
    try {
      final cubit = context.read<QuranSettingsCubit>();
      if (cubit.state.quranThemeMode == ThemeMode.dark) return true;
      if (cubit.state.quranThemeMode == ThemeMode.light) return false;
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark;
  }

  bool _resolveUseQcf(BuildContext context) {
    if (useQcf != null) return useQcf!;
    if (ayah.segments.isEmpty) return false;
    final hasValidQcf = ayah.segments.every((s) => s.qcfText.trim().isNotEmpty);
    if (!hasValidQcf) return false;

    try {
      final cubit = context.read<QuranCubit>();
      return cubit.isFontLoaded(ayah.pageNumber);
    } catch (_) {
      // In headless test or non-bloc context, default to false so Amiri backup is used
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _resolveDarkMode(context);
    final isQcf = _resolveUseQcf(context);
    final surahName = getSurahName(ayah.id.surahNumber);
    final ayahNumberArabic = _toArabicDigits(ayah.id.ayahNumber);

    // QCF vs Backup text & typography resolution
    final qcfFont = QuranCubit.getFontFamilyForPage(ayah.pageNumber);
    final String displayText = isQcf
        ? ayah.segments.map((s) => s.qcfText).join(' ')
        : '${ayah.uthmaniText} ۝$ayahNumberArabic';

    final textLength = displayText.length;
    final fontSize = _calculateFontSize(textLength, isQcf);
    final String targetFontFamily = isQcf ? qcfFont : 'Amiri';
    final List<String> fallbackFonts = isQcf
        ? const ['Amiri', 'Tajawal']
        : const ['Tajawal'];
    final double textLineHeight = isQcf ? 2.2 : 2.4;

    // Theme-driven Color Palette (Matching Mushaf Day / Night mode)
    final cardBorderColor = dark
        ? const Color(0xFF2E2E36)
        : AppColors.secondaryGold.withValues(alpha: 0.45);

    final gradientColors = dark
        ? const [Color(0xFF222226), Color(0xFF161619), Color(0xFF111113)]
        : const [Color(0xFFFCFAF2), Color(0xFFFFFCE6), Color(0xFFF5F0DC)];

    final surahTitleColor = dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF2A2012);
    final ayahBadgeBg = dark
        ? const Color(0xFF1F1F24)
        : const Color(0xFFF3ECE0);
    final ayahBadgeBorder = dark
        ? const Color(0xFF383842)
        : AppColors.secondaryGold.withValues(alpha: 0.35);
    final ayahBadgeTextColor = dark
        ? const Color(0xFFB5ADA0)
        : const Color(0xFF8C6D1F);

    final ayahTextColor = dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1A1A1A);

    // Night Mode: Flat Silver Logo container & attribution text
    // Day Mode: Traditional Gold container & warm brown attribution text
    final footerLogoBg = dark
        ? const Color(0xFF222226)
        : const Color.fromARGB(0, 255, 252, 248);
    final footerLogoBorder = dark
        ? const Color(0xFF484852)
        : AppColors.secondaryGold.withValues(alpha: 0.4);
    final footerTextColor = dark
        ? const Color(0xFFB0B0B8)
        : const Color(0xFF7A6B55);

    final double surahFrameWidth = width * 0.86;
    final double surahFrameHeight = surahFrameWidth / 8.16;

    final Widget ayahContent = Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.08, vertical: 24.0),
      child: Center(
        child: Text(
          displayText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: targetFontFamily,
            fontFamilyFallback: fallbackFonts,
            fontSize: fontSize,
            height: textLineHeight,
            fontWeight: FontWeight.normal,
            wordSpacing: isQcf ? -3.0 : 0.0,
            letterSpacing: isQcf ? -0.5 : 0.0,
            color: ayahTextColor,
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cardBorderColor, width: 1.5),
          gradient: RadialGradient(
            center: const Alignment(0, -0.1),
            radius: 1.15,
            colors: gradientColors,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36.0, vertical: 36.0),
          child: Column(
            mainAxisSize: height != null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Top Section: Authentic Mushaf Surah Header Banner + Metadata
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: surahFrameWidth,
                    height: surahFrameHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/svgs/Sura_border.svg',
                          width: surahFrameWidth,
                          height: surahFrameHeight,
                          fit: BoxFit.fill,
                          colorFilter: ColorFilter.mode(
                            dark
                                ? const Color(0xFF383840)
                                : AppColors.secondaryGold.withValues(
                                    alpha: 0.85,
                                  ),
                            BlendMode.srcIn,
                          ),
                        ),
                        // Surah Calligraphy (Enlarged)
                        Text(
                          _getQcfSurahName(ayah.id.surahNumber),
                          style: TextStyle(
                            fontFamily: 'QCF_BSML',
                            fontFamilyFallback: const ['Thuluth', 'Amiri'],
                            fontSize: 68,
                            color: surahTitleColor,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Ayah & Page metadata badge (Enlarged)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ayahBadgeBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ayahBadgeBorder, width: 1.2),
                    ),
                    child: Text(
                      'سورة $surahName • الآية ${ayah.id.ayahNumber} • صفحة ${ayah.pageNumber}',
                      style: TextStyle(
                        fontFamily: 'Amiri',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: ayahBadgeTextColor,
                      ),
                    ),
                  ),
                ],
              ),

              // 2. Central Section: Quranic Ayah (Tight content-fitting when height is null)
              if (height != null)
                Expanded(
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: ayahContent),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: ayahContent,
                ),
              Divider(
                thickness: 1,
                endIndent: width * 0.03,
                indent: width * 0.03,
                color: dark ? const Color(0xFFD6D6DC) : AppColors.secondaryGold,
              ),
              const SizedBox(height: 24),
              // 3. Footer Section: Hafiz Al-Ahd App Branding (Enlarged, Flat Silver in Dark Mode)
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Icon Container
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: footerLogoBg,
                      borderRadius: BorderRadius.circular(20),
                      // border: Border.all(color: footerLogoBorder, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? 0.4 : 0.08,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child:
                        logoWidget ??
                        Image.asset(
                          'assets/images/app_icon_transparent.png',
                          fit: BoxFit.contain,
                          color: dark ? const Color(0xFFD6D6DC) : null,
                          colorBlendMode: dark ? BlendMode.srcIn : null,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.auto_stories_rounded,
                            color: dark
                                ? const Color(0xFFD6D6DC)
                                : AppColors.secondaryGold,
                            size: 40,
                          ),
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'بواســطة تــطــبــيــق حـــــافــظ الـــعــهــد',
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: footerTextColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
