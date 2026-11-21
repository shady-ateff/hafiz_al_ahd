import 'package:equatable/equatable.dart';
import 'download_progress.dart';
import 'quran_download_queue_status.dart';

/// Live telemetry progress model for full-Quran library downloads (QA.6).
class QuranDownloadQueueProgress extends Equatable {
  /// Unique identifier of the associated queue.
  final String queueId;

  /// Reciter identifier.
  final String reciterId;

  /// Current queue lifecycle status.
  final QuranDownloadQueueStatus status;

  /// Total Surah count in the queue (always 114).
  final int totalItems;

  /// Completed or verified-skipped Surah count (0..114).
  final int completedItems;

  /// Surah number currently being processed (1..114), or null if idle.
  final int? activeSurahNumber;

  /// Zero-based position of the active Surah (0..113), or null if idle.
  final int? activeSurahPosition;

  /// Live transfer telemetry of the currently active single Surah.
  final DownloadProgress? activeItemProgress;

  /// Aggregate completion ratio across the entire Quran (0.0 .. 1.0).
  final double aggregateRatio;

  /// Total transferred bytes across the entire library so far.
  final int downloadedBytes;

  /// Total expected bytes for the library, or null if indeterminate.
  final int? totalExpectedBytes;

  /// Instantaneous/smoothed download transfer rate in bytes per second.
  final double? speedBytesPerSecond;

  /// Estimated time remaining to complete the queue, or null if unknown.
  final Duration? estimatedRemainingDuration;

  /// Most recent error message if an item or the queue failed.
  final String? lastError;

  const QuranDownloadQueueProgress({
    required this.queueId,
    required this.reciterId,
    required this.status,
    this.totalItems = 114,
    this.completedItems = 0,
    this.activeSurahNumber,
    this.activeSurahPosition,
    this.activeItemProgress,
    this.aggregateRatio = 0.0,
    this.downloadedBytes = 0,
    this.totalExpectedBytes,
    this.speedBytesPerSecond,
    this.estimatedRemainingDuration,
    this.lastError,
  });

  /// Factory for an initial idle/pending progress state.
  factory QuranDownloadQueueProgress.initial({
    required String queueId,
    required String reciterId,
    int? totalExpectedBytes,
  }) {
    return QuranDownloadQueueProgress(
      queueId: queueId,
      reciterId: reciterId,
      status: QuranDownloadQueueStatus.pending,
      totalExpectedBytes: totalExpectedBytes,
    );
  }

  /// Whether the queue has concluded.
  bool get isTerminal => status.isTerminal;

  /// Whether the queue is actively transferring.
  bool get isRunning => status.isRunning;

  /// Whether the queue completed downloading all tracks.
  bool get isCompleted => status.isCompleted;

  /// Percentage integer representation (0..100).
  int get aggregatePercentage => (aggregateRatio * 100).toInt().clamp(0, 100);

  QuranDownloadQueueProgress copyWith({
    String? queueId,
    String? reciterId,
    QuranDownloadQueueStatus? status,
    int? totalItems,
    int? completedItems,
    int? activeSurahNumber,
    int? activeSurahPosition,
    DownloadProgress? activeItemProgress,
    double? aggregateRatio,
    int? downloadedBytes,
    int? totalExpectedBytes,
    double? speedBytesPerSecond,
    Duration? estimatedRemainingDuration,
    String? lastError,
  }) {
    return QuranDownloadQueueProgress(
      queueId: queueId ?? this.queueId,
      reciterId: reciterId ?? this.reciterId,
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      activeSurahNumber: activeSurahNumber ?? this.activeSurahNumber,
      activeSurahPosition: activeSurahPosition ?? this.activeSurahPosition,
      activeItemProgress: activeItemProgress ?? this.activeItemProgress,
      aggregateRatio: aggregateRatio ?? this.aggregateRatio,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalExpectedBytes: totalExpectedBytes ?? this.totalExpectedBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      estimatedRemainingDuration:
          estimatedRemainingDuration ?? this.estimatedRemainingDuration,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  List<Object?> get props => [
        queueId,
        reciterId,
        status,
        totalItems,
        completedItems,
        activeSurahNumber,
        activeSurahPosition,
        activeItemProgress,
        aggregateRatio,
        downloadedBytes,
        totalExpectedBytes,
        speedBytesPerSecond,
        estimatedRemainingDuration,
        lastError,
      ];
}
