import '../../domain/entities/quran_page.dart';

class QuranPageModel extends QuranPage {
  QuranPageModel({
    required super.pageNumber,
    required List<QuranLineModel> super.lines,
  });
}

class QuranLineModel extends QuranLine {
  const QuranLineModel({
    required super.lineNumber,
    required super.surahNumber,
    required super.text,
  });
}
