import '../../domain/entities/playback_position.dart';

/// Data model representing the last listening playback position with JSON serialization support.
class PlaybackPositionModel extends PlaybackPosition {
  PlaybackPositionModel({
    required super.reciterId,
    required super.surahNumber,
    required super.positionMs,
    required super.currentAyahNumber,
    super.durationMs,
    super.updatedAt,
  });

  factory PlaybackPositionModel.fromJson(Map<String, dynamic> json) {
    return PlaybackPositionModel(
      reciterId: json['reciter_id']?.toString() ?? '',
      surahNumber: (json['surah_number'] as num?)?.toInt() ?? 1,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      currentAyahNumber: (json['current_ayah_number'] as num?)?.toInt() ?? 1,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  factory PlaybackPositionModel.fromEntity(PlaybackPosition entity) {
    return PlaybackPositionModel(
      reciterId: entity.reciterId,
      surahNumber: entity.surahNumber,
      positionMs: entity.positionMs,
      currentAyahNumber: entity.currentAyahNumber,
      durationMs: entity.durationMs,
      updatedAt: entity.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'reciter_id': reciterId,
        'surah_number': surahNumber,
        'position_ms': positionMs,
        'current_ayah_number': currentAyahNumber,
        if (durationMs != null) 'duration_ms': durationMs,
        'updated_at': updatedAt.toIso8601String(),
      };
}
