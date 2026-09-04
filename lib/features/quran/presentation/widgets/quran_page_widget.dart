import 'package:flutter/material.dart';
import '../../domain/entities/quran_page.dart';
import '../cubit/quran_cubit.dart';

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

    return Container(
      color: const Color(0xffFFFCE6), // لون خلفية المصحف الورقي
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Center(
        child: isFontLoaded
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: page.lines.map((line) {
                    return Text(
                      line.text,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: 40, // حجم ثابت كبير نسبياً، الـ FittedBox هيصغره للشاشة
                        color: Colors.black,
                        height: 1.5, // لضبط المسافة بين السطور بشكل جميل
                      ),
                    );
                  }).toList(),
                ),
              )
            : const CircularProgressIndicator(color: Colors.black),
      ),
    );
  }
}
