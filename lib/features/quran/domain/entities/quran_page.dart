class QuranPage {
  final int pageNumber;
  final List<PageLine> lines;

  QuranPage({
    required this.pageNumber,
    required this.lines,
  });
}

class PageLine {
  final int lineNumber;
  final String text; // الـ QCF Text

  PageLine({
    required this.lineNumber,
    required this.text,
  });
}
