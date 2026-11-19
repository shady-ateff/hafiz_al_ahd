import 'package:equatable/equatable.dart';

/// The persistent lifecycle status of a downloaded Quran Surah audio file in SQLite storage.
///
/// In accordance with QA.5 Phase 5.1/5.2 specifications:
/// - Persisted database statuses: `downloading`, `paused`, `verifying`, `completed`, `failed`, `cancelled`.
/// - Internal / transitional backward-compatible statuses: `idle`, `preparing`, `promoting`, `missing`, `corrupted`.
/// - Explicitly EXCLUDED from persisted database:
///   - `notDownloaded`: This is a derived presentation state when no database record exists.
///   - `queued`: Deferred beyond QA.5 single-surah scope (strictly no multi-surah queue in QA.5).
enum AudioDownloadStatus {
  idle,
  preparing,
  downloading,
  paused,
  verifying,
  promoting,
  completed,
  failed,
  cancelled,
  missing,
  corrupted;

  /// Authoritative whitelist of statuses persisted in SQLite table `quran_audio_downloads`.
  static const Set<AudioDownloadStatus> persistedStatuses = {
    AudioDownloadStatus.downloading,
    AudioDownloadStatus.paused,
    AudioDownloadStatus.verifying,
    AudioDownloadStatus.completed,
    AudioDownloadStatus.failed,
    AudioDownloadStatus.cancelled,
  };

  /// Whether this status is valid for database persistence in QA.5.
  bool get isPersisted => persistedStatuses.contains(this);

  /// Whether the download lifecycle has successfully completed.
  bool get isCompleted => this == AudioDownloadStatus.completed;

  /// Whether the download is in an active transfer, preparation, or verification state.
  bool get isActive =>
      this == AudioDownloadStatus.preparing ||
      this == AudioDownloadStatus.downloading ||
      this == AudioDownloadStatus.verifying ||
      this == AudioDownloadStatus.promoting;

  /// Whether the download has concluded (successfully or unsuccessfully).
  bool get isTerminal =>
      this == AudioDownloadStatus.completed ||
      this == AudioDownloadStatus.failed ||
      this == AudioDownloadStatus.cancelled;

  /// Whether the download can currently be paused.
  bool get isPausable => this == AudioDownloadStatus.downloading;

  /// Whether the download can be resumed or retried.
  bool get isResumable =>
      this == AudioDownloadStatus.paused ||
      this == AudioDownloadStatus.failed ||
      this == AudioDownloadStatus.cancelled;
}

/// Derived presentation state for UI display.
///
/// Distinct from persisted database lifecycle.
enum AudioDownloadDisplayStatus {
  /// No record exists in database or physical file is absent.
  notDownloaded,

  /// File is actively transferring bytes.
  downloading,

  /// Download is currently paused.
  paused,

  /// File integrity verification or atomic promotion in progress.
  verifying,

  /// File is fully verified, promoted, and playable locally.
  completed,

  /// Download or verification encountered a terminal error.
  failed,

  /// Download was cancelled by user.
  cancelled;

  /// Maps an optional persisted [AudioDownloadStatus] to the UI display state.
  static AudioDownloadDisplayStatus fromPersisted(AudioDownloadStatus? status) {
    if (status == null) return AudioDownloadDisplayStatus.notDownloaded;
    switch (status) {
      case AudioDownloadStatus.downloading:
        return AudioDownloadDisplayStatus.downloading;
      case AudioDownloadStatus.paused:
        return AudioDownloadDisplayStatus.paused;
      case AudioDownloadStatus.verifying:
      case AudioDownloadStatus.promoting:
      case AudioDownloadStatus.preparing:
        return AudioDownloadDisplayStatus.verifying;
      case AudioDownloadStatus.completed:
        return AudioDownloadDisplayStatus.completed;
      case AudioDownloadStatus.failed:
      case AudioDownloadStatus.corrupted:
        return AudioDownloadDisplayStatus.failed;
      case AudioDownloadStatus.cancelled:
        return AudioDownloadDisplayStatus.cancelled;
      case AudioDownloadStatus.idle:
      case AudioDownloadStatus.missing:
        return AudioDownloadDisplayStatus.notDownloaded;
    }
  }
}

/// Represents a persistent record of a downloaded Surah audio file on the local device.
class AudioDownload extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Reciter identifier (e.g. "7").
  final String reciterId;

  /// Path relative to the Quran audio storage root (e.g. "reciter_7/surah_001.mp3").
  final String localRelativePath;

  /// Temporary relative path during download or staging (e.g. ".staging/reciter_7_surah_001.tmp").
  final String? tempRelativePath;

  /// Current download lifecycle status.
  final AudioDownloadStatus status;

  /// Actual verified byte size physically written on disk.
  final int actualSizeBytes;

  /// Authoritative expected total byte size if known (null if chunked or unknown).
  final int? expectedSizeBytes;

  /// Optional SHA-256 hex digest for integrity verification.
  final String? sha256;

  /// Whether the file transfer integrity was verified through the pipeline via full-file SHA-256.
  ///
  /// In accordance with Rev 7 contracts:
  /// - `true`: Verified transfer through download pipeline with matching full-file SHA-256.
  /// - `false`: Legacy v1 asset (which may have a fingerprint hash) or unverified asset.
  final bool transferIntegrityVerified;

  /// HTTP ETag response validator.
  final String? etag;

  /// HTTP Last-Modified response validator.
  final String? lastModified;

  /// Last error message encountered during transfer or promotion.
  final String? lastError;

  /// Immutable timestamp when the download record was initiated or created.
  final DateTime downloadedAt;

  /// Timestamp when the download was fully verified and promoted to destination (null until completed).
  final DateTime? completedAt;

  AudioDownload({
    required this.surahNumber,
    required this.reciterId,
    required this.localRelativePath,
    this.tempRelativePath,
    required this.status,
    required this.actualSizeBytes,
    this.expectedSizeBytes,
    this.sha256,
    this.transferIntegrityVerified = false,
    this.etag,
    this.lastModified,
    this.lastError,
    DateTime? downloadedAt,
    DateTime? completedAt,
  })  : downloadedAt = downloadedAt ?? DateTime.now(),
        completedAt = completedAt ??
            (status == AudioDownloadStatus.completed
                ? (downloadedAt ?? DateTime.now())
                : null) {
    // 1. Boundary & Security Validations
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
    if (reciterId.contains('..') || reciterId.contains('/') || reciterId.contains(r'\')) {
      throw ArgumentError.value(
        reciterId,
        'reciterId',
        'Path traversal characters in reciterId are strictly prohibited: $reciterId',
      );
    }
    if (localRelativePath.contains('..') ||
        localRelativePath.startsWith('/') ||
        localRelativePath.startsWith(r'\')) {
      throw ArgumentError.value(
        localRelativePath,
        'localRelativePath',
        'Path traversal and absolute paths are strictly prohibited: $localRelativePath',
      );
    }
    if (tempRelativePath != null &&
        (tempRelativePath!.contains('..') ||
            tempRelativePath!.startsWith('/') ||
            tempRelativePath!.startsWith(r'\'))) {
      throw ArgumentError.value(
        tempRelativePath,
        'tempRelativePath',
        'Path traversal and absolute paths are strictly prohibited: $tempRelativePath',
      );
    }
    if (actualSizeBytes < 0) {
      throw ArgumentError.value(
        actualSizeBytes,
        'actualSizeBytes',
        'actualSizeBytes cannot be negative',
      );
    }
    if (expectedSizeBytes != null && expectedSizeBytes! < 0) {
      throw ArgumentError.value(
        expectedSizeBytes,
        'expectedSizeBytes',
        'expectedSizeBytes cannot be negative',
      );
    }

    // 2. Entity Invariant: Completed State Consistency
    if (status == AudioDownloadStatus.completed) {
      if (actualSizeBytes <= 0) {
        throw ArgumentError.value(
          actualSizeBytes,
          'actualSizeBytes',
          'A completed download cannot have zero or negative byte size.',
        );
      }
      if (expectedSizeBytes != null && actualSizeBytes != expectedSizeBytes) {
        throw ArgumentError.value(
          actualSizeBytes,
          'actualSizeBytes',
          'Completed download actualSizeBytes ($actualSizeBytes) does not match expectedSizeBytes ($expectedSizeBytes).',
        );
      }
      if (this.completedAt == null) {
        throw ArgumentError.value(
          this.completedAt,
          'completedAt',
          'A completed download must specify a non-null completedAt timestamp.',
        );
      }
    } else {
      // Non-completed downloads CANNOT carry a completedAt timestamp
      if (completedAt != null) {
        throw ArgumentError.value(
          completedAt,
          'completedAt',
          'completedAt must be null when status is not completed.',
        );
      }
    }

    // 3. Entity Invariant: Transfer Integrity Verification Consistency
    if (transferIntegrityVerified) {
      if (status != AudioDownloadStatus.completed) {
        throw ArgumentError.value(
          status,
          'status',
          'transferIntegrityVerified can only be true for completed downloads.',
        );
      }
      if (sha256 == null || sha256!.trim().isEmpty) {
        throw ArgumentError.value(
          sha256,
          'sha256',
          'transferIntegrityVerified requires an authoritative non-empty SHA-256 digest.',
        );
      }
    }
  }

  /// Whether the file is verified and ready for offline playback.
  bool get isPlayable => status == AudioDownloadStatus.completed && actualSizeBytes > 0;

  AudioDownload copyWith({
    int? surahNumber,
    String? reciterId,
    String? localRelativePath,
    String? tempRelativePath,
    AudioDownloadStatus? status,
    int? actualSizeBytes,
    int? expectedSizeBytes,
    String? sha256,
    bool? transferIntegrityVerified,
    String? etag,
    String? lastModified,
    String? lastError,
    DateTime? downloadedAt,
    DateTime? completedAt,
  }) {
    final nextStatus = status ?? this.status;
    final nextCompletedAt = completedAt ??
        (nextStatus == AudioDownloadStatus.completed
            ? (this.completedAt ?? DateTime.now())
            : null);

    return AudioDownload(
      surahNumber: surahNumber ?? this.surahNumber,
      reciterId: reciterId ?? this.reciterId,
      localRelativePath: localRelativePath ?? this.localRelativePath,
      tempRelativePath: tempRelativePath ?? this.tempRelativePath,
      status: nextStatus,
      actualSizeBytes: actualSizeBytes ?? this.actualSizeBytes,
      expectedSizeBytes: expectedSizeBytes ?? this.expectedSizeBytes,
      sha256: sha256 ?? this.sha256,
      transferIntegrityVerified:
          transferIntegrityVerified ?? this.transferIntegrityVerified,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      lastError: lastError ?? this.lastError,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      completedAt: nextCompletedAt,
    );
  }

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        localRelativePath,
        tempRelativePath,
        status,
        actualSizeBytes,
        expectedSizeBytes,
        sha256,
        transferIntegrityVerified,
        etag,
        lastModified,
        lastError,
        downloadedAt,
        completedAt,
      ];
}
