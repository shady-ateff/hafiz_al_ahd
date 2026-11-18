import 'package:equatable/equatable.dart';

/// The lifecycle status of a downloaded Quran Surah audio file.
enum AudioDownloadStatus {
  idle,
  preparing,
  downloading,
  verifying,
  promoting,
  completed,
  failed,
  cancelled,
  missing,
  corrupted;

  bool get isCompleted => this == AudioDownloadStatus.completed;
  bool get isActive =>
      this == AudioDownloadStatus.preparing ||
      this == AudioDownloadStatus.downloading ||
      this == AudioDownloadStatus.verifying ||
      this == AudioDownloadStatus.promoting;
}

/// Represents a persistent record of a downloaded Surah audio file on the local device.
class AudioDownload extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Reciter identifier (e.g. "7").
  final String reciterId;

  /// Path relative to the Quran audio storage root (e.g. "reciter_7/surah_001.mp3").
  final String localRelativePath;

  /// Current download lifecycle status.
  final AudioDownloadStatus status;

  /// Actual verified byte size on disk.
  final int actualSizeBytes;

  /// Optional SHA-256 hex digest for integrity verification.
  final String? sha256;

  /// Timestamp when the download was completed or recorded.
  final DateTime downloadedAt;

  AudioDownload({
    required this.surahNumber,
    required this.reciterId,
    required this.localRelativePath,
    required this.status,
    required this.actualSizeBytes,
    this.sha256,
    DateTime? downloadedAt,
  }) : downloadedAt = downloadedAt ?? DateTime.now() {
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
    if (localRelativePath.contains('..') ||
        localRelativePath.startsWith('/') ||
        localRelativePath.startsWith('\\')) {
      throw ArgumentError.value(
        localRelativePath,
        'localRelativePath',
        'Path traversal and absolute paths are strictly prohibited: $localRelativePath',
      );
    }
    if (actualSizeBytes < 0) {
      throw ArgumentError.value(
        actualSizeBytes,
        'actualSizeBytes',
        'actualSizeBytes cannot be negative',
      );
    }
  }

  /// Whether the file is verified and ready for offline playback.
  bool get isPlayable => status == AudioDownloadStatus.completed && actualSizeBytes > 0;

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        localRelativePath,
        status,
        actualSizeBytes,
        sha256,
        downloadedAt,
      ];
}
