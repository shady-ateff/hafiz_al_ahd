import 'package:equatable/equatable.dart';
import 'quran_download_queue_item.dart';
import 'quran_download_queue_status.dart';

/// Represents a persistent full-Quran download queue for a single reciter.
class QuranDownloadQueue extends Equatable {
  /// Total number of Surahs in the complete Quran library.
  static const int kTotalSurahs = 114;

  /// Unique identifier of the queue (UUID string).
  final String id;

  /// Identifier of the reciter whose full library is being downloaded.
  final String reciterId;

  /// Aggregate lifecycle status of the queue.
  final QuranDownloadQueueStatus status;

  /// Total items in the queue (always 114).
  final int totalItems;

  /// Number of items that have reached terminal completion or were skipped.
  final int completedItems;

  /// Sum of expected byte sizes, or null if any item is indeterminate.
  final int? totalExpectedBytes;

  /// Total transferred bytes across all items in the queue.
  final int downloadedBytes;

  /// Queue creation timestamp.
  final DateTime createdAt;

  /// Last queue update timestamp.
  final DateTime updatedAt;

  /// Timestamp when the queue reached full completion, if completed.
  final DateTime? completedAt;

  /// Ordered list of Surah queue items (positions 0..113).
  final List<QuranDownloadQueueItem> items;

  QuranDownloadQueue({
    required this.id,
    required this.reciterId,
    required this.status,
    this.totalItems = kTotalSurahs,
    this.completedItems = 0,
    this.totalExpectedBytes,
    this.downloadedBytes = 0,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    List<QuranDownloadQueueItem> items = const [],
  }) : items = List<QuranDownloadQueueItem>.unmodifiable(items) {
    if (totalItems != kTotalSurahs) {
      throw ArgumentError.value(
        totalItems,
        'totalItems',
        'totalItems must be exactly $kTotalSurahs (received: $totalItems)',
      );
    }
    if (completedItems < 0 || completedItems > kTotalSurahs) {
      throw ArgumentError.value(
        completedItems,
        'completedItems',
        'completedItems must be between 0 and $kTotalSurahs (received: $completedItems)',
      );
    }
    if (downloadedBytes < 0) {
      throw ArgumentError.value(
        downloadedBytes,
        'downloadedBytes',
        'downloadedBytes cannot be negative (received: $downloadedBytes)',
      );
    }
    if (totalExpectedBytes != null && totalExpectedBytes! < 0) {
      throw ArgumentError.value(
        totalExpectedBytes,
        'totalExpectedBytes',
        'totalExpectedBytes cannot be negative (received: $totalExpectedBytes)',
      );
    }
    if (items.isNotEmpty && items.length != kTotalSurahs) {
      throw ArgumentError.value(
        items.length,
        'items.length',
        'When provided, items list must contain exactly $kTotalSurahs items (received: ${items.length})',
      );
    }
  }

  /// Whether the queue is currently in an active state (`pending`, `running`, `paused`).
  bool get isActive => status.isActive;

  /// Whether the queue has concluded (`completed`, `failed`, `cancelled`).
  bool get isTerminal => status.isTerminal;

  /// Whether the queue can be resumed or retried.
  bool get isResumable => status.isResumable;

  /// Whether all 114 Surahs have reached verified completion.
  bool get isFullyCompleted {
    if (completedItems != totalItems) return false;
    if (items.isEmpty) return status == QuranDownloadQueueStatus.completed;
    return items.every((i) => i.isCompletedOrSkipped);
  }

  /// Aggregate completion progress ratio between 0.0 and 1.0.
  ///
  /// Uses byte-weighted ratio if total expected bytes is determinate,
  /// otherwise falls back to completed-items count ratio.
  double get aggregateRatio {
    if (isFullyCompleted || status == QuranDownloadQueueStatus.completed) {
      return 1.0;
    }
    if (totalExpectedBytes != null && totalExpectedBytes! > 0) {
      return (downloadedBytes / totalExpectedBytes!).clamp(0.0, 1.0);
    }
    return (completedItems / totalItems).clamp(0.0, 1.0);
  }

  /// Returns the currently active item, if any item is `running`.
  QuranDownloadQueueItem? get activeItem {
    try {
      return items.firstWhere((i) => i.status.isRunning);
    } catch (_) {
      return null;
    }
  }

  /// Returns the next pending item according to queue sequence (`position ASC`), or null.
  QuranDownloadQueueItem? get nextPendingItem {
    try {
      return items.firstWhere((i) => i.status.isPending);
    } catch (_) {
      return null;
    }
  }

  /// Returns all items that failed in the current queue run.
  List<QuranDownloadQueueItem> get failedItems {
    return items.where((i) => i.status.isFailed).toList();
  }

  /// Returns all items that completed or were verified-skipped.
  List<QuranDownloadQueueItem> get completedOrSkippedItems {
    return items.where((i) => i.isCompletedOrSkipped).toList();
  }

  /// Creates a copy with optionally updated fields.
  QuranDownloadQueue copyWith({
    String? id,
    String? reciterId,
    QuranDownloadQueueStatus? status,
    int? totalItems,
    int? completedItems,
    int? totalExpectedBytes,
    int? downloadedBytes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    List<QuranDownloadQueueItem>? items,
  }) {
    return QuranDownloadQueue(
      id: id ?? this.id,
      reciterId: reciterId ?? this.reciterId,
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      totalExpectedBytes: totalExpectedBytes ?? this.totalExpectedBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        reciterId,
        status,
        totalItems,
        completedItems,
        totalExpectedBytes,
        downloadedBytes,
        createdAt,
        updatedAt,
        completedAt,
        items,
      ];
}
