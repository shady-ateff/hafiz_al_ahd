import 'package:equatable/equatable.dart';
import 'audio_download.dart';

/// Represents real-time download progress and transfer telemetry for an individual Surah.
class DownloadProgress extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Reciter identifier (e.g. "7").
  final String reciterId;

  /// Current download lifecycle status.
  final AudioDownloadStatus status;

  /// Actual number of bytes physically written to disk.
  final int downloadedBytes;

  /// Expected total file length in bytes (null if chunked or unknown).
  final int? expectedTotalBytes;

  /// Download transfer speed in bytes per second.
  final double? downloadSpeedBytesPerSecond;

  /// Estimated time remaining until transfer completion.
  final Duration? estimatedTimeRemaining;

  /// Last error message encountered during transfer.
  final String? lastError;

  /// Timestamp when the download was initiated.
  final DateTime startedAt;

  /// Timestamp of the latest progress update.
  final DateTime updatedAt;

  DownloadProgress({
    required this.surahNumber,
    required this.reciterId,
    required this.status,
    required this.downloadedBytes,
    this.expectedTotalBytes,
    this.downloadSpeedBytesPerSecond,
    this.estimatedTimeRemaining,
    this.lastError,
    DateTime? startedAt,
    DateTime? updatedAt,
  })  : startedAt = startedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now() {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114',
      );
    }
    if (reciterId.trim().isEmpty) {
      throw ArgumentError.value(reciterId, 'reciterId', 'reciterId cannot be empty');
    }
    if (downloadedBytes < 0) {
      throw ArgumentError.value(
        downloadedBytes,
        'downloadedBytes',
        'downloadedBytes cannot be negative',
      );
    }
    if (expectedTotalBytes != null && expectedTotalBytes! < 0) {
      throw ArgumentError.value(
        expectedTotalBytes,
        'expectedTotalBytes',
        'expectedTotalBytes cannot be negative when provided',
      );
    }
  }

  /// Whether the total size is unknown (chunked encoding or missing Content-Length).
  bool get isIndeterminate => expectedTotalBytes == null || expectedTotalBytes! <= 0;

  /// Progress ratio clamped strictly between 0.0 and 1.0.
  ///
  /// INVARIANT: Unknown total size is NEVER represented as a fabricated 100% or zero-byte completion.
  double get progressRatio {
    if (isIndeterminate) return 0.0;
    final ratio = downloadedBytes / expectedTotalBytes!;
    return ratio.clamp(0.0, 1.0);
  }

  /// Progress percentage (0 to 100).
  int get progressPercentage => (progressRatio * 100).round();

  /// Whether the download is currently active and transferring bytes.
  bool get isDownloading => status == AudioDownloadStatus.downloading;

  /// Whether the download completed successfully.
  bool get isCompleted => status == AudioDownloadStatus.completed;

  /// Derived presentation status for UI display.
  AudioDownloadDisplayStatus get displayStatus =>
      AudioDownloadDisplayStatus.fromPersisted(status);

  /// Creates a clean initial progress record before transfer begins.
  factory DownloadProgress.initial({
    required int surahNumber,
    required String reciterId,
    int? expectedTotalBytes,
  }) {
    final now = DateTime.now();
    return DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.idle,
      downloadedBytes: 0,
      expectedTotalBytes: expectedTotalBytes,
      startedAt: now,
      updatedAt: now,
    );
  }

  DownloadProgress copyWith({
    int? surahNumber,
    String? reciterId,
    AudioDownloadStatus? status,
    int? downloadedBytes,
    int? expectedTotalBytes,
    double? downloadSpeedBytesPerSecond,
    Duration? estimatedTimeRemaining,
    String? lastError,
    DateTime? startedAt,
    DateTime? updatedAt,
  }) {
    return DownloadProgress(
      surahNumber: surahNumber ?? this.surahNumber,
      reciterId: reciterId ?? this.reciterId,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      expectedTotalBytes: expectedTotalBytes ?? this.expectedTotalBytes,
      downloadSpeedBytesPerSecond:
          downloadSpeedBytesPerSecond ?? this.downloadSpeedBytesPerSecond,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      lastError: lastError ?? this.lastError,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        status,
        downloadedBytes,
        expectedTotalBytes,
        downloadSpeedBytesPerSecond,
        estimatedTimeRemaining,
        lastError,
        startedAt,
        updatedAt,
      ];
}
