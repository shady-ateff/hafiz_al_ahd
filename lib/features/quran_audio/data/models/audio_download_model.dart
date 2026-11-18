import '../../domain/entities/audio_download.dart';

/// Data model representing a downloaded Surah audio record with JSON serialization support.
class AudioDownloadModel extends AudioDownload {
  AudioDownloadModel({
    required super.surahNumber,
    required super.reciterId,
    required super.localRelativePath,
    required super.status,
    required super.actualSizeBytes,
    super.sha256,
    super.downloadedAt,
  });

  factory AudioDownloadModel.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    final status = AudioDownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => AudioDownloadStatus.idle,
    );

    return AudioDownloadModel(
      surahNumber: (json['surah_number'] as num?)?.toInt() ?? 1,
      reciterId: json['reciter_id']?.toString() ?? '',
      localRelativePath: json['local_relative_path'] as String? ?? '',
      status: status,
      actualSizeBytes: (json['actual_size_bytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String?,
      downloadedAt: json['downloaded_at'] != null
          ? DateTime.tryParse(json['downloaded_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  factory AudioDownloadModel.fromEntity(AudioDownload entity) {
    return AudioDownloadModel(
      surahNumber: entity.surahNumber,
      reciterId: entity.reciterId,
      localRelativePath: entity.localRelativePath,
      status: entity.status,
      actualSizeBytes: entity.actualSizeBytes,
      sha256: entity.sha256,
      downloadedAt: entity.downloadedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'surah_number': surahNumber,
        'reciter_id': reciterId,
        'local_relative_path': localRelativePath,
        'status': status.name,
        'actual_size_bytes': actualSizeBytes,
        if (sha256 != null) 'sha256': sha256,
        'downloaded_at': downloadedAt.toIso8601String(),
      };

  AudioDownloadModel copyWith({
    int? surahNumber,
    String? reciterId,
    String? localRelativePath,
    AudioDownloadStatus? status,
    int? actualSizeBytes,
    String? sha256,
    DateTime? downloadedAt,
  }) {
    return AudioDownloadModel(
      surahNumber: surahNumber ?? this.surahNumber,
      reciterId: reciterId ?? this.reciterId,
      localRelativePath: localRelativePath ?? this.localRelativePath,
      status: status ?? this.status,
      actualSizeBytes: actualSizeBytes ?? this.actualSizeBytes,
      sha256: sha256 ?? this.sha256,
      downloadedAt: downloadedAt ?? this.downloadedAt,
    );
  }
}
