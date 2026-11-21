import 'package:equatable/equatable.dart';

/// Represents the terminal status outcome of a single-Surah download execution.
enum SingleSurahResultStatus {
  completed,
  failed,
  paused,
  cancelled;

  bool get isCompleted => this == SingleSurahResultStatus.completed;
  bool get isFailed => this == SingleSurahResultStatus.failed;
  bool get isPaused => this == SingleSurahResultStatus.paused;
  bool get isCancelled => this == SingleSurahResultStatus.cancelled;
}

/// Explicit terminal result model returned by `downloadSurahAndWait` in QA.6.
///
/// Separates the live progress telemetry stream from the authoritative completion result.
class SingleSurahDownloadResult extends Equatable {
  final int surahNumber;
  final String reciterId;
  final SingleSurahResultStatus status;
  final String? filePath;
  final int? totalBytes;
  final String? sha256;
  final String? errorMessage;
  final int? downloadedBytes;

  const SingleSurahDownloadResult._({
    required this.surahNumber,
    required this.reciterId,
    required this.status,
    this.filePath,
    this.totalBytes,
    this.sha256,
    this.errorMessage,
    this.downloadedBytes,
  });

  /// Factory for a successfully completed and authoritatively verified download.
  factory SingleSurahDownloadResult.completed({
    required int surahNumber,
    required String reciterId,
    required String filePath,
    required int totalBytes,
    required String sha256,
  }) {
    return SingleSurahDownloadResult._(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: SingleSurahResultStatus.completed,
      filePath: filePath,
      totalBytes: totalBytes,
      sha256: sha256,
      downloadedBytes: totalBytes,
    );
  }

  /// Factory for a failed download.
  factory SingleSurahDownloadResult.failed({
    required int surahNumber,
    required String reciterId,
    required String errorMessage,
    int? downloadedBytes,
  }) {
    return SingleSurahDownloadResult._(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: SingleSurahResultStatus.failed,
      errorMessage: errorMessage,
      downloadedBytes: downloadedBytes,
    );
  }

  /// Factory for a paused download (partial staging bytes preserved).
  factory SingleSurahDownloadResult.paused({
    required int surahNumber,
    required String reciterId,
    required int downloadedBytes,
  }) {
    return SingleSurahDownloadResult._(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: SingleSurahResultStatus.paused,
      downloadedBytes: downloadedBytes,
    );
  }

  /// Factory for a cancelled download.
  factory SingleSurahDownloadResult.cancelled({
    required int surahNumber,
    required String reciterId,
  }) {
    return SingleSurahDownloadResult._(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: SingleSurahResultStatus.cancelled,
    );
  }

  bool get isCompleted => status.isCompleted;
  bool get isFailed => status.isFailed;
  bool get isPaused => status.isPaused;
  bool get isCancelled => status.isCancelled;

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        status,
        filePath,
        totalBytes,
        sha256,
        errorMessage,
        downloadedBytes,
      ];
}
