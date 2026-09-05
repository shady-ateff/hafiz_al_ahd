import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../../domain/entities/quran_page.dart';
import '../cubit/quran_cubit.dart';
import '../../data/datasources/quran_page_metadata.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/datasources/surah_names.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/quran_settings_cubit.dart';

class QuranPageWidget extends StatelessWidget {
  final QuranPage page;
  final bool isFontLoaded;

  const QuranPageWidget({
    super.key,
    required this.page,
    required this.isFontLoaded,
  });

  bool _isDarkMode(BuildContext context, ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = QuranCubit.getFontFamilyForPage(page.pageNumber);
    final themeMode = context.watch<QuranSettingsCubit>().state.quranThemeMode;
    final isDark = _isDarkMode(context, themeMode);

    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xffFFFCE6);
    final textColor = isDark ? const Color(0xFFF5F5DC) : Colors.black87;
    final primaryTextColor = isDark ? const Color(0xffD4AF37) : Colors.black87;

    final meta =
        quranPageMetadata[page.pageNumber] ??
        const QuranPageMetadata(surahName: "", juzNumber: 0);
    final surahName = meta.surahName;
    final juzNumber = meta.juzNumber;

    return SafeArea(
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xffD4AF37), width: 1.0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الجزء $juzNumber',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  Text(
                    'سورة $surahName',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: isFontLoaded
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final screenRatio =
                              constraints.maxHeight / constraints.maxWidth;
                          final dynamicHeight = (screenRatio * 1.0).clamp(
                            1.45,
                            3.0,
                          );

                          return FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: 700,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _buildPageLines(
                                  fontFamily,
                                  dynamicHeight,
                                  textColor,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : CircularProgressIndicator(color: primaryTextColor),
              ),
            ),
            // Footer Page Number
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 120,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotatedBox(
                    quarterTurns: 1,
                    child: SvgPicture.asset(
                      'assets/svgs/Juz_border.svg',
                      width: 150,
                      height: 150,
                      fit: BoxFit.contain,
                      colorFilter: ColorFilter.mode(
                        primaryTextColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  Text(
                    '${page.pageNumber}',
                    style: TextStyle(
                      fontFamily: 'Thuluth Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPageLines(
    String fontFamily,
    double dynamicHeight,
    Color textColor,
  ) {
    final List<Widget> widgets = [];
    int expectedLine = 1;
    final int maxLines = (page.pageNumber == 1 || page.pageNumber == 2)
        ? 7
        : 15;

    for (var line in page.lines) {
      if (line.lineNumber > expectedLine) {
        int gapSize = line.lineNumber - expectedLine;

        if (gapSize == 2) {
          widgets.add(
            _buildSurahHeader(line.surahNumber, dynamicHeight, textColor),
          );
          widgets.add(_buildBasmalah(dynamicHeight, textColor));
        } else if (gapSize == 1) {
          if (line.surahNumber == 1 || line.surahNumber == 9) {
            widgets.add(
              _buildSurahHeader(line.surahNumber, dynamicHeight, textColor),
            );
          } else {
            widgets.add(_buildBasmalah(dynamicHeight, textColor));
          }
        } else {
          for (int i = 0; i < gapSize; i++) {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        }
        expectedLine = line.lineNumber;
      }

      widgets.add(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 40,
              color: textColor,
              height: dynamicHeight,
              wordSpacing: -3.5,
              letterSpacing: -0.5,
            ),
          ),
        ),
      );
      expectedLine = line.lineNumber + 1;
    }

    if (expectedLine <= maxLines) {
      int gapSize = maxLines - expectedLine + 1;
      int nextSurah = page.lines.isNotEmpty
          ? page.lines.last.surahNumber + 1
          : 1;

      if (nextSurah <= 114) {
        if (gapSize == 2) {
          widgets.add(_buildSurahHeader(nextSurah, dynamicHeight, textColor));
          if (nextSurah != 9) {
            widgets.add(_buildBasmalah(dynamicHeight, textColor));
          } else {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        } else if (gapSize == 1) {
          widgets.add(_buildSurahHeader(nextSurah, dynamicHeight, textColor));
        } else {
          for (int i = 0; i < gapSize; i++) {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        }
      } else {
        for (int i = 0; i < gapSize; i++) {
          widgets.add(SizedBox(height: 40 * dynamicHeight));
        }
      }
    }

    return widgets;
  }

  String _getQcfSurahName(int surahNumber) {
    String surahName = "";
    if (64396 + surahNumber >= 64434) {
      surahName = String.fromCharCode(64429 + surahNumber);
    } else {
      surahName = String.fromCharCode(64396 + surahNumber);
    }
    return "${String.fromCharCode(64396)} $surahName";
  }

  Widget _buildSurahHeader(
    int surahNumber,
    double dynamicHeight,
    Color textColor,
  ) {
    return Container(
      height: 44 * dynamicHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            'assets/svgs/Sura_border.svg',
            width: 700,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
          ),
          Text(
            _getQcfSurahName(surahNumber),
            style: TextStyle(
              fontFamily: 'QCF_BSML',
              fontSize: 50,
              color: textColor,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasmalah(double dynamicHeight, Color textColor) {
    return Container(
      height: 45 * dynamicHeight,
      alignment: Alignment.center,
      child: Text(
        "ﱁ ﱂ ﱃ ﱄ",
        style: TextStyle(fontFamily: 'QCF2001', fontSize: 40, color: textColor),
      ),
    );
  }

  bool _isSurahStart(QuranPage page, int surahNumber) {
    return surahStartPages[surahNumber - 1] == page.pageNumber;
  }
}
