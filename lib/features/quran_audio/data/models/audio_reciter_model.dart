import '../../domain/entities/audio_reciter.dart';

/// Data model representing a Quran reciter with JSON serialization support.
class AudioReciterModel extends AudioReciter {
  AudioReciterModel({
    required super.id,
    required super.name,
    required super.arabicName,
    super.style,
    super.qirat,
    super.description,
    super.provider,
    super.availableFormat,
  });

  factory AudioReciterModel.fromJson(Map<String, dynamic> json) {
    // Supports Quran Foundation API format as well as stored cache format
    final id = json['id']?.toString() ?? '';
    final name = json['name'] as String? ?? '';
    
    // Arabic name might be in translated_name or arabic_name
    String arabicName = json['arabic_name'] as String? ?? '';
    if (arabicName.isEmpty && json['translated_name'] is Map) {
      final tn = json['translated_name'] as Map;
      if (tn['language_name'] == 'arabic') {
        arabicName = tn['name']?.toString() ?? '';
      }
    }
    if (arabicName.isEmpty) {
      arabicName = name;
    }

    String? style;
    if (json['style'] is Map) {
      style = json['style']['name'] as String?;
    } else if (json['style'] is String) {
      style = json['style'] as String;
    }

    String? qirat;
    if (json['qirat'] is Map) {
      qirat = json['qirat']['name'] as String?;
    } else if (json['qirat'] is String) {
      qirat = json['qirat'] as String;
    }

    return AudioReciterModel(
      id: id,
      name: name,
      arabicName: arabicName,
      style: style,
      qirat: qirat,
      description: json['description'] as String?,
      provider: json['provider'] as String? ?? 'quran_foundation',
      availableFormat: json['available_format'] as String? ?? 'mp3',
    );
  }

  factory AudioReciterModel.fromEntity(AudioReciter entity) {
    return AudioReciterModel(
      id: entity.id,
      name: entity.name,
      arabicName: entity.arabicName,
      style: entity.style,
      qirat: entity.qirat,
      description: entity.description,
      provider: entity.provider,
      availableFormat: entity.availableFormat,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arabic_name': arabicName,
        if (style != null) 'style': style,
        if (qirat != null) 'qirat': qirat,
        if (description != null) 'description': description,
        'provider': provider,
        'available_format': availableFormat,
      };
}
