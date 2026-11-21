import 'package:equatable/equatable.dart';

/// Distinguishes between single-Surah download notifications and full-Quran library queue notifications.
enum DownloadNotificationType {
  singleSurah,
  fullQuran,
}

/// Granular phases of a download operation reflecting the QA.5 & QA.6 lifecycles.
enum DownloadNotificationPhase {
  starting,
  downloading,
  verifying,
  promoting,
  paused,
  completed,
  failed,
  cancelled,
}

extension DownloadNotificationPhaseX on DownloadNotificationPhase {
  bool get isOngoing =>
      this == DownloadNotificationPhase.starting ||
      this == DownloadNotificationPhase.downloading ||
      this == DownloadNotificationPhase.verifying ||
      this == DownloadNotificationPhase.promoting;

  bool get isTerminal =>
      this == DownloadNotificationPhase.completed ||
      this == DownloadNotificationPhase.failed ||
      this == DownloadNotificationPhase.cancelled;

  bool get isIndeterminate =>
      this == DownloadNotificationPhase.starting ||
      this == DownloadNotificationPhase.verifying ||
      this == DownloadNotificationPhase.promoting;
}

/// Normalized event model emitted when download progress or state changes.
class DownloadNotificationEvent extends Equatable {
  /// Unique session token for the active operation to guard against stale events (C4).
  final String sessionId;

  /// Type of download (single Surah or full Quran queue).
  final DownloadNotificationType type;

  /// Current phase of the download.
  final DownloadNotificationPhase phase;

  /// The Surah number currently being processed (1..114).
  final int surahNumber;

  /// Canonical Arabic name of the Surah (e.g. "البقرة").
  final String surahName;

  /// Unique reciter ID.
  final String reciterId;

  /// Canonical Arabic name of the reciter (e.g. "مشاري راشد العفاسي").
  final String reciterName;

  /// Progress ratio from 0.0 to 1.0, or null if indeterminate.
  final double? progressRatio;

  /// Total downloaded bytes so far.
  final int downloadedBytes;

  /// Expected total bytes, or null if indeterminate.
  final int? totalBytes;

  /// Total number of completed Surahs (for queue, 0..114; for single Surah: 0 or 1).
  final int completedSurahs;

  /// Total Surahs in the operation (1 for single, 114 for full Quran).
  final int totalSurahs;

  /// Optional user-friendly error message if phase is failed.
  final String? errorMessage;

  /// Timestamp of the event.
  final DateTime timestamp;

  const DownloadNotificationEvent({
    required this.sessionId,
    required this.type,
    required this.phase,
    required this.surahNumber,
    required this.surahName,
    required this.reciterId,
    required this.reciterName,
    this.progressRatio,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.completedSurahs = 0,
    this.totalSurahs = 1,
    this.errorMessage,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
        sessionId,
        type,
        phase,
        surahNumber,
        surahName,
        reciterId,
        reciterName,
        progressRatio,
        downloadedBytes,
        totalBytes,
        completedSurahs,
        totalSurahs,
        errorMessage,
        timestamp,
      ];
}
