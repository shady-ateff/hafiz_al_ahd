import 'package:share_plus/share_plus.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';

typedef TextShareFunction = Future<ShareResult> Function(
  String text, {
  String? subject,
});

typedef FilesShareFunction = Future<ShareResult> Function(
  List<XFile> files, {
  String? text,
  String? subject,
});

/// Service responsible for formatting and sharing Quran Ayahs
/// as plain text or branded image files.
class QuranShareService {
  final TextShareFunction _textShare;
  final FilesShareFunction _filesShare;

   QuranShareService({
    TextShareFunction? textShare,
    FilesShareFunction? filesShare,
  })  : _textShare = textShare ?? Share.share,      _filesShare = filesShare ?? Share.shareXFiles;

  /// Formats the Ayah according to canonical text sharing rules:
  /// ﴿ {ayah.uthmaniText} ﴾
  ///
  /// [سورة {surahName} - الآية {ayahNumber}]
  ///
  /// مشاركة من تطبيق حافظ العهد
  static String formatAyahForShare(QuranAyah ayah) {
    final surahName = getSurahName(ayah.id.surahNumber);
    return '﴿ ${ayah.uthmaniText} ﴾\n\n'
        '[سورة $surahName - الآية ${ayah.id.ayahNumber}]\n\n'
        'مشاركة من تطبيق حافظ العهد';
  }

  /// Shares the [ayah] as formatted text via native share sheet.
  /// Returns [ShareResultStatus] to distinguish success, dismissal, or failure.
  Future<ShareResultStatus> shareText(QuranAyah ayah) async {
    try {
      final formattedText = formatAyahForShare(ayah);
      final surahName = getSurahName(ayah.id.surahNumber);
      final result = await _textShare(
        formattedText,
        subject: 'سورة $surahName - الآية ${ayah.id.ayahNumber}',
      );
      return result.status;
    } catch (_) {
      return ShareResultStatus.unavailable;
    }
  }

  /// Shares the image file located at [filePath] with Ayah attribution.
  Future<ShareResultStatus> shareImageFile(
    String filePath,
    QuranAyah ayah,
  ) async {
    try {
      final surahName = getSurahName(ayah.id.surahNumber);
      final result = await _filesShare(
        [XFile(filePath)],
        text: '﴿ ${ayah.uthmaniText} ﴾\n[سورة $surahName - الآية ${ayah.id.ayahNumber}]',
        subject: 'سورة $surahName - الآية ${ayah.id.ayahNumber}',
      );
      return result.status;
    } catch (_) {
      return ShareResultStatus.unavailable;
    }
  }
}

