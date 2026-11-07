import 'package:flutter/services.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';

typedef ClipboardDataSetter = Future<void> Function(ClipboardData data);

/// Lightweight service responsible for formatting and copying Quran Ayahs
/// to the platform clipboard without external dependencies.
class QuranClipboardService {
  final ClipboardDataSetter _clipboardSetter;

  const QuranClipboardService({
    ClipboardDataSetter? clipboardSetter,
  }) : _clipboardSetter = clipboardSetter ?? Clipboard.setData;

  /// Formats the [QuranAyah] into standard Arabic text with full tashkeel,
  /// enclosed in ornate brackets with Surah name and Ayah number attribution.
  ///
  /// Format:
  /// ﴿ {ayah.uthmaniText} ﴾
  /// [سورة {surahName} - الآية {ayahNumber}]
  static String formatAyah(QuranAyah ayah) {
    final surahName = getSurahName(ayah.id.surahNumber);
    return '﴿ ${ayah.uthmaniText} ﴾\n[سورة $surahName - الآية ${ayah.id.ayahNumber}]';
  }

  /// Copies the formatted [ayah] text to the platform clipboard.
  /// Returns `true` if successful, or `false` if an error occurs.
  Future<bool> copyAyah(QuranAyah ayah) async {
    try {
      final formattedText = formatAyah(ayah);
      await _clipboardSetter(ClipboardData(text: formattedText));
      return true;
    } catch (_) {
      return false;
    }
  }
}

