import 'package:equatable/equatable.dart';
import 'quran_download_queue_status.dart';

/// Represents a single Surah track item in the full-Quran download queue.
class QuranDownloadQueueItem extends Equatable {
  /// Unique identifier of the queue item (e.g. `${queueId}_$surahNumber`).
  final String id;

  /// Foreign key referencing the parent queue ID.
  final String queueId;

  /// Surah number in the Quran (1..114).
  final int surahNumber;

  /// Zero-based sequential position index in the queue (0..113).
  final int position;

  /// Current lifecycle status of this item.
  final QuranDownloadQueueItemStatus status;

  /// Advisory/expected byte size from catalog, if available.
  final int? expectedBytes;

  /// Actual number of bytes transferred so far.
  final int downloadedBytes;

  /// Number of download attempts executed for this Surah.
  final int attemptCount;

  /// Most recent error message if the item failed.
  final String? lastError;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime updatedAt;

  QuranDownloadQueueItem({
    required this.id,
    required this.queueId,
    required this.surahNumber,
    required this.position,
    required this.status,
    this.expectedBytes,
    this.downloadedBytes = 0,
    this.attemptCount = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114 (received: $surahNumber)',
      );
    }
    if (position < 0 || position > 113) {
      throw ArgumentError.value(
        position,
        'position',
        'position must be between 0 and 113 (received: $position)',
      );
    }
    if (downloadedBytes < 0) {
      throw ArgumentError.value(
        downloadedBytes,
        'downloadedBytes',
        'downloadedBytes cannot be negative (received: $downloadedBytes)',
      );
    }
    if (attemptCount < 0) {
      throw ArgumentError.value(
        attemptCount,
        'attemptCount',
        'attemptCount cannot be negative (received: $attemptCount)',
      );
    }
    if (expectedBytes != null && expectedBytes! < 0) {
      throw ArgumentError.value(
        expectedBytes,
        'expectedBytes',
        'expectedBytes cannot be negative (received: $expectedBytes)',
      );
    }
  }

  /// Transfer progress ratio between 0.0 and 1.0, or null if expected size is indeterminate.
  double? get progressRatio {
    if (status == QuranDownloadQueueItemStatus.completed ||
        status == QuranDownloadQueueItemStatus.skipped) {
      return 1.0;
    }
    if (expectedBytes != null && expectedBytes! > 0) {
      return (downloadedBytes / expectedBytes!).clamp(0.0, 1.0);
    }
    return null;
  }

  /// Whether this item represents a satisfied completion condition.
  bool get isCompletedOrSkipped => status.isCompletedOrSkipped;

  /// Creates a copy with optionally updated fields.
  QuranDownloadQueueItem copyWith({
    String? id,
    String? queueId,
    int? surahNumber,
    int? position,
    QuranDownloadQueueItemStatus? status,
    int? expectedBytes,
    int? downloadedBytes,
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuranDownloadQueueItem(
      id: id ?? this.id,
      queueId: queueId ?? this.queueId,
      surahNumber: surahNumber ?? this.surahNumber,
      position: position ?? this.position,
      status: status ?? this.status,
      expectedBytes: expectedBytes ?? this.expectedBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        queueId,
        surahNumber,
        position,
        status,
        expectedBytes,
        downloadedBytes,
        attemptCount,
        lastError,
        createdAt,
        updatedAt,
      ];
}
