import '../../domain/entities/audio_download.dart';

/// Data model representing a downloaded Surah audio record with JSON and SQLite serialization support.
class AudioDownloadModel extends AudioDownload {
  AudioDownloadModel({
    required super.surahNumber,
    required super.reciterId,
    required super.localRelativePath,
    super.tempRelativePath,
    required super.status,
    required super.actualSizeBytes,
    super.expectedSizeBytes,
    super.sha256,
    super.transferIntegrityVerified = false,
    super.etag,
    super.lastModified,
    super.lastError,
    super.downloadedAt,
    super.completedAt,
  });

  factory AudioDownloadModel.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    final status = AudioDownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => AudioDownloadStatus.idle,
    );

    final downloadedAt = json['downloaded_at'] != null
        ? (json['downloaded_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['downloaded_at'] as int)
            : DateTime.tryParse(json['downloaded_at'].toString()) ?? DateTime.now())
        : DateTime.now();

    final completedAt = json['completed_at'] != null
        ? (json['completed_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['completed_at'] as int)
            : DateTime.tryParse(json['completed_at'].toString()))
        : (status == AudioDownloadStatus.completed ? downloadedAt : null);

    return AudioDownloadModel(
      surahNumber: (json['surah_number'] as num?)?.toInt() ?? 1,
      reciterId: json['reciter_id']?.toString() ?? '',
      localRelativePath: json['local_relative_path'] as String? ?? '',
      tempRelativePath: json['temp_relative_path'] as String?,
      status: status,
      actualSizeBytes: (json['actual_size_bytes'] as num?)?.toInt() ?? 0,
      expectedSizeBytes: (json['expected_size_bytes'] as num?)?.toInt(),
      sha256: json['sha256'] as String?,
      transferIntegrityVerified: json['transfer_integrity_verified'] == 1 ||
          json['transfer_integrity_verified'] == true,
      etag: json['etag'] as String?,
      lastModified: json['last_modified'] as String?,
      lastError: json['last_error'] as String?,
      downloadedAt: downloadedAt,
      completedAt: completedAt,
    );
  }

  factory AudioDownloadModel.fromEntity(AudioDownload entity) {
    return AudioDownloadModel(
      surahNumber: entity.surahNumber,
      reciterId: entity.reciterId,
      localRelativePath: entity.localRelativePath,
      tempRelativePath: entity.tempRelativePath,
      status: entity.status,
      actualSizeBytes: entity.actualSizeBytes,
      expectedSizeBytes: entity.expectedSizeBytes,
      sha256: entity.sha256,
      transferIntegrityVerified: entity.transferIntegrityVerified,
      etag: entity.etag,
      lastModified: entity.lastModified,
      lastError: entity.lastError,
      downloadedAt: entity.downloadedAt,
      completedAt: entity.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'surah_number': surahNumber,
        'reciter_id': reciterId,
        'local_relative_path': localRelativePath,
        if (tempRelativePath != null) 'temp_relative_path': tempRelativePath,
        'status': status.name,
        'actual_size_bytes': actualSizeBytes,
        if (expectedSizeBytes != null) 'expected_size_bytes': expectedSizeBytes,
        if (sha256 != null) 'sha256': sha256,
        'transfer_integrity_verified': transferIntegrityVerified ? 1 : 0,
        if (etag != null) 'etag': etag,
        if (lastModified != null) 'last_modified': lastModified,
        if (lastError != null) 'last_error': lastError,
        'downloaded_at': downloadedAt.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };

  @override
  AudioDownloadModel copyWith({
    int? surahNumber,
    String? reciterId,
    String? localRelativePath,
    String? tempRelativePath,
    AudioDownloadStatus? status,
    int? actualSizeBytes,
    int? expectedSizeBytes,
    String? sha256,
    bool? transferIntegrityVerified,
    String? etag,
    String? lastModified,
    String? lastError,
    DateTime? downloadedAt,
    DateTime? completedAt,
  }) {
    final nextStatus = status ?? this.status;
    final nextCompletedAt = completedAt ??
        (nextStatus == AudioDownloadStatus.completed
            ? (this.completedAt ?? DateTime.now())
            : null);

    return AudioDownloadModel(
      surahNumber: surahNumber ?? this.surahNumber,
      reciterId: reciterId ?? this.reciterId,
      localRelativePath: localRelativePath ?? this.localRelativePath,
      tempRelativePath: tempRelativePath ?? this.tempRelativePath,
      status: nextStatus,
      actualSizeBytes: actualSizeBytes ?? this.actualSizeBytes,
      expectedSizeBytes: expectedSizeBytes ?? this.expectedSizeBytes,
      sha256: sha256 ?? this.sha256,
      transferIntegrityVerified:
          transferIntegrityVerified ?? this.transferIntegrityVerified,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      lastError: lastError ?? this.lastError,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      completedAt: nextCompletedAt,
    );
  }
}
