import '../../domain/entities/quran_download_queue.dart';
import '../../domain/entities/quran_download_queue_status.dart';
import 'quran_download_queue_item_model.dart';

/// Data model representing a full-Quran download queue in SQLite table `quran_download_queues`.
class QuranDownloadQueueModel extends QuranDownloadQueue {
  QuranDownloadQueueModel({
    required super.id,
    required super.reciterId,
    required super.status,
    super.totalItems,
    super.completedItems,
    super.totalExpectedBytes,
    super.downloadedBytes,
    required super.createdAt,
    required super.updatedAt,
    super.completedAt,
    super.items,
  });

  /// Factory from SQLite row map and optional ordered item list.
  factory QuranDownloadQueueModel.fromMap(
    Map<String, dynamic> map, [
    List<QuranDownloadQueueItemModel> items = const [],
  ]) {
    return QuranDownloadQueueModel(
      id: map['id'] as String,
      reciterId: map['reciter_id'] as String,
      status: QuranDownloadQueueStatus.fromString(map['status'] as String),
      totalItems: (map['total_items'] as int?) ?? QuranDownloadQueue.kTotalSurahs,
      completedItems: (map['completed_items'] as int?) ?? 0,
      totalExpectedBytes: map['total_expected_bytes'] as int?,
      downloadedBytes: (map['downloaded_bytes'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      items: items,
    );
  }

  /// Converts queue model to SQLite column-value map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reciter_id': reciterId,
      'status': status.toDbString(),
      'total_items': totalItems,
      'completed_items': completedItems,
      'total_expected_bytes': totalExpectedBytes,
      'downloaded_bytes': downloadedBytes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  /// Factory from domain entity.
  factory QuranDownloadQueueModel.fromEntity(QuranDownloadQueue queue) {
    return QuranDownloadQueueModel(
      id: queue.id,
      reciterId: queue.reciterId,
      status: queue.status,
      totalItems: queue.totalItems,
      completedItems: queue.completedItems,
      totalExpectedBytes: queue.totalExpectedBytes,
      downloadedBytes: queue.downloadedBytes,
      createdAt: queue.createdAt,
      updatedAt: queue.updatedAt,
      completedAt: queue.completedAt,
      items: queue.items.map((i) => QuranDownloadQueueItemModel.fromEntity(i)).toList(),
    );
  }

  /// Converts to base domain entity.
  QuranDownloadQueue toEntity() {
    return QuranDownloadQueue(
      id: id,
      reciterId: reciterId,
      status: status,
      totalItems: totalItems,
      completedItems: completedItems,
      totalExpectedBytes: totalExpectedBytes,
      downloadedBytes: downloadedBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
      items: items,
    );
  }
}
