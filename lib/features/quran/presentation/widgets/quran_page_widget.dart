import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../../domain/entities/quran_page.dart';
import '../cubit/quran_cubit.dart';
import '../../data/datasources/quran_page_metadata.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/datasources/surah_names.dart'; // 👈 استيراد أسماء السور

class QuranPageWidget extends StatelessWidget {
  final QuranPage page;
  final bool isFontLoaded;

  const QuranPageWidget({
    super.key,
    required this.page,
    required this.isFontLoaded,
  });

  @override
  Widget build(BuildContext context) {
    final fontFamily = QuranCubit.getFontFamilyForPage(page.pageNumber);

    // جلب بيانات الصفحة (السورة والجزء) من الخريطة المحلية الخفيفة
    final meta =
        quranPageMetadata[page.pageNumber] ??
        const QuranPageMetadata(surahName: "", juzNumber: 0);
    final surahName = meta.surahName;
    final juzNumber = meta.juzNumber;

    return Container(
      color: const Color(0xffFFFCE6), // لون خلفية المصحف الورقي
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: Column(
        children: [
          // الهيدر الثابت للسورة والجزء
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
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'سورة $surahName',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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
                        // حساب نسبة الشاشة (الطول مقسوم على العرض)
                        final screenRatio =
                            constraints.maxHeight / constraints.maxWidth;

                        // المعادلة السحرية: جعل ارتفاع السطر يتفاعل مع طول الشاشة
                        // الحد الأدنى 1.45 (عشان التابلت) والحد الأقصى 2.0 (للموبايلات الطويلة جداً)
                        final dynamicHeight = (screenRatio * 1.0).clamp(
                          1.45,
                          3.0,
                        );

                        return FittedBox(
                          fit: BoxFit
                              .contain, // 👈 contain لضمان عدم القص أبداً في أي شاشة
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _buildPageLines(
                              fontFamily,
                              dynamicHeight,
                            ),
                          ),
                        );
                      },
                    )
                  : const CircularProgressIndicator(color: Colors.black),
            ),
          ),
          // برواز رفيع حول رقم الصفحة
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 120,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotatedBox(
                  quarterTurns: 1, // دوران 90 درجة
                  child: SvgPicture.asset(
                    'assets/svgs/Juz_border.svg',
                    width: 150,
                    height: 150,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      Colors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                Text(
                  '${page.pageNumber}',
                  style: const TextStyle(
                    fontFamily: 'Thuluth Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // الدالة السحرية لرسم الأسطر ورصد الفراغات لوضع الفواصل والبسملة
  List<Widget> _buildPageLines(String fontFamily, double dynamicHeight) {
    final List<Widget> widgets = [];
    int expectedLine = 1;
    final int maxLines = (page.pageNumber == 1 || page.pageNumber == 2)
        ? 7
        : 15;

    for (var line in page.lines) {
      if (line.lineNumber > expectedLine) {
        int gapSize = line.lineNumber - expectedLine;

        if (gapSize == 2) {
          widgets.add(_buildSurahHeader(line.surahNumber, dynamicHeight));
          widgets.add(_buildBasmalah(dynamicHeight));
        } else if (gapSize == 1) {
          if (line.surahNumber == 9) {
            // التوبة
            widgets.add(_buildSurahHeader(line.surahNumber, dynamicHeight));
          } else if (line.surahNumber == 1) {
            // الفاتحة
            widgets.add(_buildSurahHeader(line.surahNumber, dynamicHeight));
          } else {
            // سطر واحد مفقود والسورة بدأت؟ يعني برواز السورة كان في الصفحة السابقة! وهذا السطر هو البسملة
            widgets.add(_buildBasmalah(dynamicHeight));
          }
        } else {
          // فجوة أكبر من سطرين؟ نضع فراغات للحفاظ على التوازن
          for (int i = 0; i < gapSize; i++) {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        }
      }

      // إضافة نص الآية الفعلي
      widgets.add(
        Text(
          line.text,
          textAlign: TextAlign.center, // توسيط الآيات لتعويض التمدد
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 40, // حجم الخط المرجعي للـ QCF
            color: Colors.black,
            height: dynamicHeight,
            wordSpacing: -3.5,
            letterSpacing: -0.5,
          ),
        ),
      );
      expectedLine = line.lineNumber + 1;
    }

    // إكمال الصفحة إلى 15 سطراً بدقة إذا كان هناك فراغ في الأسفل
    if (expectedLine <= maxLines) {
      int gapSize = maxLines - expectedLine + 1;
      int nextSurah = page.lines.isNotEmpty
          ? page.lines.last.surahNumber + 1
          : 1;

      if (nextSurah <= 114) {
        if (gapSize == 2) {
          widgets.add(_buildSurahHeader(nextSurah, dynamicHeight));
          if (nextSurah != 9) {
            widgets.add(_buildBasmalah(dynamicHeight));
          } else {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        } else if (gapSize == 1) {
          widgets.add(_buildSurahHeader(nextSurah, dynamicHeight));
        } else {
          for (int i = 0; i < gapSize; i++) {
            widgets.add(SizedBox(height: 40 * dynamicHeight));
          }
        }
      } else {
        // نهاية المصحف
        for (int i = 0; i < gapSize; i++) {
          widgets.add(SizedBox(height: 40 * dynamicHeight));
        }
      }
    }

    return widgets;
  }

  String _getQcfSurahName(int surahNumber) {
    // خوارزمية مجمع الملك فهد لاستخراج رمز اسم السورة من خط QCF_BSML
    String surahName = "";
    if (64396 + surahNumber >= 64434) {
      surahName = String.fromCharCode(64429 + surahNumber);
    } else {
      surahName = String.fromCharCode(64396 + surahNumber);
    }
    // الرمز 64396 هو غالباً كلمة "سورة" بالرسم العثماني في هذا الخط
    return "${String.fromCharCode(64396)} $surahName";
  }

  Widget _buildSurahHeader(int surahNumber, double dynamicHeight) {
    return Container(
      width: 700, // 👈 لا نستخدم double.infinity لأن الـ Column موجود داخل FittedBox
      height: 44 * dynamicHeight, 
      child: Stack(
        alignment: Alignment.center,
        children: [
          // إطار السورة الأصلي
          SvgPicture.asset(
            'assets/svgs/Sura_border.svg',
            width: 700,
            fit: BoxFit.fill,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
          // اسم السورة بخط مجمع الملك فهد QCF_BSML
          Padding(
            padding: const EdgeInsets.only(
              bottom: 6.0,
            ), // لرفع الخط قليلا ليوسطن
            child: Text(
              _getQcfSurahName(surahNumber),
              style: const TextStyle(
                fontFamily: 'QCF_BSML', // خط أسماء السور الرسمي من المجمع
                fontSize: 48, // حجم أكبر قليلا لرموز الـ QCF
                color: Colors.black,
                textBaseline: TextBaseline.alphabetic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasmalah(double dynamicHeight) {
    return Container(
      height: 40 * dynamicHeight, // أخذ مساحة السطر المفقود
      alignment: Alignment.center,
      child: const Text(
        "ﱁ ﱂ ﱃ ﱄ", // تم إزالة الرمز الخامس (ﱅ) الخاص برقم الآية 1
        style: TextStyle(
          fontFamily:
              'QCF2001', // الخط الذي يحتوي على البسملة مرسومة بدقة المجمع
          fontSize: 40, // نفس حجم خط الآيات
          color: Colors.black,
        ),
      ),
    );
  }
}
