class QuranPage {
  final int pageNumber;
  final List<QuranLine> lines;

  QuranPage({
    required this.pageNumber,
    required this.lines,
  });
}

class QuranLine {
  final int lineNumber;
  final int surahNumber;
  final String text;

  const QuranLine({
    required this.lineNumber,
    required this.surahNumber,
    required this.text,
  });
}
