import '../../domain/entities/quran_download_queue_item.dart';
import '../../domain/entities/quran_download_queue_status.dart';

/// Data model representing a full-Quran queue item in SQLite table `quran_download_queue_items`.
class QuranDownloadQueueItemModel extends QuranDownloadQueueItem {
  QuranDownloadQueueItemModel({
    required super.id,
    required super.queueId,
    required super.surahNumber,
    required super.position,
    required super.status,
    super.expectedBytes,
    super.downloadedBytes,
    super.attemptCount,
    super.lastError,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Factory from SQLite row map.
  factory QuranDownloadQueueItemModel.fromMap(Map<String, dynamic> map) {
    return QuranDownloadQueueItemModel(
      id: map['id'] as String,
      queueId: map['queue_id'] as String,
      surahNumber: map['surah_number'] as int,
      position: map['position'] as int,
      status: QuranDownloadQueueItemStatus.fromString(map['status'] as String),
      expectedBytes: map['expected_bytes'] as int?,
      downloadedBytes: (map['downloaded_bytes'] as int?) ?? 0,
      attemptCount: (map['attempt_count'] as int?) ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Converts model to SQLite column-value map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'queue_id': queueId,
      'surah_number': surahNumber,
      'position': position,
      'status': status.toDbString(),
      'expected_bytes': expectedBytes,
      'downloaded_bytes': downloadedBytes,
      'attempt_count': attemptCount,
      'last_error': lastError,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Factory from domain entity.
  factory QuranDownloadQueueItemModel.fromEntity(QuranDownloadQueueItem item) {
    return QuranDownloadQueueItemModel(
      id: item.id,
      queueId: item.queueId,
      surahNumber: item.surahNumber,
      position: item.position,
      status: item.status,
      expectedBytes: item.expectedBytes,
      downloadedBytes: item.downloadedBytes,
      attemptCount: item.attemptCount,
      lastError: item.lastError,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  /// Converts to base domain entity.
  QuranDownloadQueueItem toEntity() {
    return QuranDownloadQueueItem(
      id: id,
      queueId: queueId,
      surahNumber: surahNumber,
      position: position,
      status: status,
      expectedBytes: expectedBytes,
      downloadedBytes: downloadedBytes,
      attemptCount: attemptCount,
      lastError: lastError,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
