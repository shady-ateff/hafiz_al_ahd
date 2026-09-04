import '../../domain/entities/quran_page.dart';

class QuranPageModel extends QuranPage {
  QuranPageModel({
    required super.pageNumber,
    required List<PageLineModel> super.lines,
  });
}

class PageLineModel extends PageLine {
  PageLineModel({
    required super.lineNumber,
    required super.text,
  });
}
