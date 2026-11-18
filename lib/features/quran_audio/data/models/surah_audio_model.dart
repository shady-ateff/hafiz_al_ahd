import '../../domain/entities/surah_audio.dart';
import 'ayah_timing_model.dart';

/// Data model representing a Surah audio track with JSON serialization support.
class SurahAudioModel extends SurahAudio {
  SurahAudioModel({
    required super.surahNumber,
    required super.reciterId,
    required super.audioUrl,
    required super.durationMs,
    super.format,
    super.expectedContentLength,
    super.ayahTimings,
  });

  /// Parses from either internal cache JSON or Quran Foundation API `audio_files[0]` item.
  factory SurahAudioModel.fromJson(
    Map<String, dynamic> json, {
    int? fallbackSurahNumber,
    String? fallbackReciterId,
  }) {
    final surahNumber = (json['surah_number'] as num?)?.toInt() ??
        (json['chapter_id'] as num?)?.toInt() ??
        fallbackSurahNumber ??
        1;

    final reciterId = json['reciter_id']?.toString() ?? fallbackReciterId ?? '7';
    final audioUrl = json['audio_url'] as String? ?? '';
    final durationMs = (json['duration_ms'] as num?)?.toInt() ??
        (json['duration'] as num?)?.toInt() ??
        0;
    final format = json['format'] as String? ?? 'mp3';

    // Disregard API metadata file_size if corrupt or fractional, treat as optional hint
    final rawSize = json['expected_content_length'] ?? json['file_size'];
    final expectedContentLength = (rawSize is num && rawSize > 0) ? rawSize.toInt() : null;

    final List<AyahTimingModel> timings = [];
    final rawTimings = json['ayah_timings'] ?? json['verse_timings'];
    if (rawTimings is List) {
      for (final item in rawTimings) {
        if (item is Map<String, dynamic>) {
          timings.add(AyahTimingModel.fromJson(item, fallbackSurahNumber: surahNumber));
        } else if (item is Map) {
          timings.add(AyahTimingModel.fromJson(
            Map<String, dynamic>.from(item),
            fallbackSurahNumber: surahNumber,
          ));
        }
      }
    }

    return SurahAudioModel(
      surahNumber: surahNumber,
      reciterId: reciterId,
      audioUrl: audioUrl,
      durationMs: durationMs,
      format: format,
      expectedContentLength: expectedContentLength,
      ayahTimings: timings,
    );
  }

  factory SurahAudioModel.fromEntity(SurahAudio entity) {
    return SurahAudioModel(
      surahNumber: entity.surahNumber,
      reciterId: entity.reciterId,
      audioUrl: entity.audioUrl,
      durationMs: entity.durationMs,
      format: entity.format,
      expectedContentLength: entity.expectedContentLength,
      ayahTimings: entity.ayahTimings,
    );
  }

  Map<String, dynamic> toJson() => {
        'surah_number': surahNumber,
        'reciter_id': reciterId,
        'audio_url': audioUrl,
        'duration_ms': durationMs,
        'format': format,
        if (expectedContentLength != null)
          'expected_content_length': expectedContentLength,
        'ayah_timings': ayahTimings
            .map((t) => t is AyahTimingModel
                ? t.toJson()
                : AyahTimingModel.fromEntity(t).toJson())
            .toList(),
      };
}
