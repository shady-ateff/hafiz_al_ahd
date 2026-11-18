import '../../domain/entities/ayah_timing.dart';

/// Data model representing an Ayah playback timing interval with JSON serialization.
class AyahTimingModel extends AyahTiming {
  AyahTimingModel({
    required super.surahNumber,
    required super.ayahNumber,
    required super.timestampFrom,
    required super.timestampTo,
    super.duration,
  });

  /// Parses from either internal cache JSON or Quran Foundation API `verse_timings` item.
  factory AyahTimingModel.fromJson(Map<String, dynamic> json, {int? fallbackSurahNumber}) {
    int surah = (json['surah_number'] as num?)?.toInt() ?? 0;
    int ayah = (json['ayah_number'] as num?)?.toInt() ?? 0;

    // Handle Quran Foundation "verse_key": "1:2"
    if (json.containsKey('verse_key') && json['verse_key'] is String) {
      final parts = (json['verse_key'] as String).split(':');
      if (parts.length == 2) {
        surah = int.tryParse(parts[0]) ?? surah;
        ayah = int.tryParse(parts[1]) ?? ayah;
      }
    }

    if (surah == 0 && fallbackSurahNumber != null) {
      surah = fallbackSurahNumber;
    }

    final from = (json['timestamp_from'] as num?)?.toInt() ?? 0;
    final to = (json['timestamp_to'] as num?)?.toInt() ?? from;
    final dur = (json['duration'] as num?)?.toInt() ?? (to - from);

    return AyahTimingModel(
      surahNumber: surah,
      ayahNumber: ayah,
      timestampFrom: from,
      timestampTo: to,
      duration: dur,
    );
  }

  factory AyahTimingModel.fromEntity(AyahTiming entity) {
    return AyahTimingModel(
      surahNumber: entity.surahNumber,
      ayahNumber: entity.ayahNumber,
      timestampFrom: entity.timestampFrom,
      timestampTo: entity.timestampTo,
      duration: entity.duration,
    );
  }

  Map<String, dynamic> toJson() => {
        'surah_number': surahNumber,
        'ayah_number': ayahNumber,
        'timestamp_from': timestampFrom,
        'timestamp_to': timestampTo,
        'duration': duration,
      };
}
