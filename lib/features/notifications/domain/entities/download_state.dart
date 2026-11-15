import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';

/// Finite states of a remote audio download lifecycle.
enum DownloadStatus {
  /// Entry is known, but no download has started or been queued.
  idle,

  /// Download task is waiting in queue (if concurrency limits are reached).
  queued,

  /// Actively streaming bytes from HTTPS server to temporary file.
  downloading,

  /// Download finished; validating size and computing SHA-256 digest.
  verifying,

  /// Verification passed; atomically promoting file to private app storage.
  promoting,

  /// File is safely stored and registered as a valid local CustomAudioSource.
  completed,

  /// Task encountered an unrecoverable error; temporary files were cleaned up.
  failed,

  /// Task was cancelled by the user; temporary files were cleaned up.
  cancelled;

  /// Whether the task is currently active (consuming network, CPU, or I/O).
  bool get isActive =>
      this == DownloadStatus.queued ||
      this == DownloadStatus.downloading ||
      this == DownloadStatus.verifying ||
      this == DownloadStatus.promoting;

  /// Whether the task has reached an end state.
  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.cancelled;
}

/// Represents the observable runtime state of an audio download task.
class AudioDownloadTask extends Equatable {
  /// Unique catalog entry identifier (`remote:<slug>`).
  final String entryId;

  /// Current lifecycle status.
  final DownloadStatus status;

  /// Byte-level network progress.
  final DownloadProgress progress;

  /// Verified CustomAudioSource available once status == [DownloadStatus.completed].
  final CustomAudioSource? resultSource;

  /// Error information available if status == [DownloadStatus.failed].
  final AudioDownloadFailure? failure;

  const AudioDownloadTask({
    required this.entryId,
    required this.status,
    this.progress = const DownloadProgress(receivedBytes: 0),
    this.resultSource,
    this.failure,
  });

  /// Initial idle task constructor.
  factory AudioDownloadTask.idle(String entryId) => AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.idle,
      );

  /// Factory for downloading state.
  factory AudioDownloadTask.downloading({
    required String entryId,
    required DownloadProgress progress,
  }) =>
      AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.downloading,
        progress: progress,
      );

  /// Factory for verification state.
  factory AudioDownloadTask.verifying(String entryId, int totalBytes) => AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.verifying,
        progress: DownloadProgress.determinate(
          receivedBytes: totalBytes,
          totalBytes: totalBytes,
        ),
      );

  /// Factory for promotion state.
  factory AudioDownloadTask.promoting(String entryId, int totalBytes) => AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.promoting,
        progress: DownloadProgress.determinate(
          receivedBytes: totalBytes,
          totalBytes: totalBytes,
        ),
      );

  /// Factory for successful completion.
  factory AudioDownloadTask.completed({
    required String entryId,
    required CustomAudioSource source,
  }) =>
      AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.completed,
        progress: DownloadProgress.determinate(
          receivedBytes: source.fileSize,
          totalBytes: source.fileSize,
        ),
        resultSource: source,
      );

  /// Factory for failure state.
  factory AudioDownloadTask.failed({
    required String entryId,
    required AudioDownloadFailure failure,
  }) =>
      AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.failed,
        failure: failure,
      );

  /// Factory for cancelled state.
  factory AudioDownloadTask.cancelled(String entryId) => AudioDownloadTask(
        entryId: entryId,
        status: DownloadStatus.cancelled,
      );

  AudioDownloadTask copyWith({
    DownloadStatus? status,
    DownloadProgress? progress,
    CustomAudioSource? resultSource,
    AudioDownloadFailure? failure,
  }) {
    return AudioDownloadTask(
      entryId: entryId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      resultSource: resultSource ?? this.resultSource,
      failure: failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [entryId, status, progress, resultSource, failure];

  @override
  String toString() =>
      'AudioDownloadTask(entryId: $entryId, status: ${status.name}, progress: $progress)';
}

