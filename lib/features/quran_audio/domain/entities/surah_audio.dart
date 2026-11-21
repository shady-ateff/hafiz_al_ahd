import 'package:equatable/equatable.dart';
import 'ayah_timing.dart';

/// Represents the audio metadata and timing track for one complete Surah recited by a specific reciter.
class SurahAudio extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Reciter identifier (e.g. "7").
  final String reciterId;

  /// Remote URL for audio streaming / downloading.
  final String audioUrl;

  /// Total audio duration in milliseconds.
  final int durationMs;

  /// Audio container format (typically "mp3").
  final String format;

  /// Expected file content length in bytes if verified via HEAD or manifest (optional).
  final int? expectedContentLength;

  /// Sorted list of Ayah timing intervals within this Surah.
  final List<AyahTiming> ayahTimings;

  SurahAudio({
    required this.surahNumber,
    required this.reciterId,
    required this.audioUrl,
    required this.durationMs,
    this.format = 'mp3',
    this.expectedContentLength,
    List<AyahTiming>? ayahTimings,
  }) : ayahTimings = List<AyahTiming>.unmodifiable(ayahTimings ?? const []) {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114',
      );
    }
    if (reciterId.trim().isEmpty) {
      throw ArgumentError.value(reciterId, 'reciterId', 'reciterId cannot be empty');
    }
    if (audioUrl.trim().isEmpty) {
      throw ArgumentError.value(audioUrl, 'audioUrl', 'audioUrl cannot be empty');
    }
    if (durationMs < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'durationMs cannot be negative');
    }
    if (expectedContentLength != null && expectedContentLength! <= 0) {
      throw ArgumentError.value(
        expectedContentLength,
        'expectedContentLength',
        'expectedContentLength must be positive when provided',
      );
    }
  }

  /// Whether timing intervals are available for this audio track.
  bool get hasTimings => ayahTimings.isNotEmpty;

  /// Finds the timing interval for a specific Ayah number.
  AyahTiming? getTimingForAyah(int ayahNumber) {
    for (final timing in ayahTimings) {
      if (timing.ayahNumber == ayahNumber) {
        return timing;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        audioUrl,
        durationMs,
        format,
        expectedContentLength,
        ayahTimings,
      ];
}
