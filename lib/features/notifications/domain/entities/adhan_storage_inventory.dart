import 'package:flutter/foundation.dart';

/// Classifies physical files within the `adhan_sounds` directory.
enum StorageFileClassification {
  /// User-imported custom audio: `custom_{timestamp}.{ext}`.
  /// Strictly owned by the user. NEVER automatically evicted.
  userCustom,

  /// Valid remote catalog cache: `remote_{slug}_{sha24}.{ext}`.
  /// Managed as remote cache. Evictable ONLY IF not assigned to any prayer alarm.
  remoteCache,

  /// In-flight or staging download file: `.tmp/dl_{token}_{timestamp}.tmp`.
  stagingTmp,

  /// Any file that does not match expected patterns, unsupported extension,
  /// 0-byte corrupt file, or unknown naming convention.
  /// Strictly treated as unmanaged and protected from automatic eviction.
  unmanaged,
}

/// Represents a single physical audio file inspected in application storage.
@immutable
class StorageAudioFile {
  /// Relative path from app storage parent, e.g. `adhan_sounds/remote_fajr_...mp3`.
  final String relativePath;

  /// Absolute normalized physical path on disk.
  final String absolutePath;

  /// File name with extension.
  final String fileName;

  /// Actual byte length on the filesystem (never estimated).
  final int byteLength;

  /// Last modification timestamp from filesystem metadata.
  final DateTime lastModified;

  /// Ownership and lifecycle classification.
  final StorageFileClassification classification;

  /// Whether this file is locked and protected from deletion/eviction.
  final bool isProtected;

  /// Human-readable explanation of why this file is protected.
  final String? protectedReason;

  const StorageAudioFile({
    required this.relativePath,
    required this.absolutePath,
    required this.fileName,
    required this.byteLength,
    required this.lastModified,
    required this.classification,
    required this.isProtected,
    this.protectedReason,
  });

  /// Whether this file is an eligible, safe candidate for eviction.
  /// Only unprotected remoteCache files are eligible for eviction.
  bool get isSafeToEvict =>
      !isProtected && classification == StorageFileClassification.remoteCache;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageAudioFile &&
          runtimeType == other.runtimeType &&
          absolutePath == other.absolutePath &&
          byteLength == other.byteLength &&
          classification == other.classification &&
          isProtected == other.isProtected;

  @override
  int get hashCode => Object.hash(
        absolutePath,
        byteLength,
        classification,
        isProtected,
      );

  @override
  String toString() =>
      'StorageAudioFile(file: $fileName, size: $byteLength bytes, class: ${classification.name}, protected: $isProtected)';
}

/// Outcome of checking whether a download of [requiredBytes] is permitted under the quota.
@immutable
class QuotaCheckResult {
  /// Whether the required download fits within the remote cache quota.
  final bool isAllowed;

  /// The byte length requested for download.
  final int requiredBytes;

  /// The available unreserved quota headroom.
  final int availableQuotaBytes;

  /// Current effective usage (cached remote files + in-flight reservations).
  final int currentUsageBytes;

  /// The maximum allowed remote cache quota limit.
  final int quotaLimitBytes;

  /// The number of bytes by which the quota is exceeded (0 if [isAllowed]).
  final int deficitBytes;

  /// Suggested safe eviction candidates to free enough headroom for this download.
  final List<StorageAudioFile> suggestedEvictionCandidates;

  const QuotaCheckResult({
    required this.isAllowed,
    required this.requiredBytes,
    required this.availableQuotaBytes,
    required this.currentUsageBytes,
    required this.quotaLimitBytes,
    required this.deficitBytes,
    this.suggestedEvictionCandidates = const [],
  });

  @override
  String toString() =>
      'QuotaCheckResult(allowed: $isAllowed, required: $requiredBytes, available: $availableQuotaBytes, deficit: $deficitBytes)';
}

/// Comprehensive, immutable snapshot of the `adhan_sounds` storage state.
@immutable
class AdhanStorageInventory {
  /// Total physical bytes used by all files in `adhan_sounds/` (including all classifications).
  final int totalDirectoryBytes;

  /// Actual byte length consumed by valid remote cache files.
  final int remoteCacheBytes;

  /// Actual byte length consumed by user-imported custom audio.
  final int userCustomBytes;

  /// Actual byte length consumed by staging/in-flight temporary files.
  final int stagingTmpBytes;

  /// Actual byte length consumed by unmanaged / unknown files.
  final int unmanagedBytes;

  /// Reserved byte capacity for currently in-flight active downloads.
  final int reservedInFlightBytes;

  /// Remote cache quota ceiling (default 150 MiB = 157,286,400 bytes).
  final int remoteCacheQuotaBytes;

  /// All physical files discovered and classified during this scan.
  final List<StorageAudioFile> files;

  /// Set of normalized relative paths currently assigned to any active prayer alarm.
  final Set<String> activeAlarmPaths;

  /// Temporary files in `.tmp/` identified as abandoned (not active, older than threshold).
  final List<StorageAudioFile> abandonedTmpFiles;

  /// Safe candidates for remote cache eviction, ordered by priority (oldest modified first).
  /// Strictly excludes active alarm files, user custom audio, and unmanaged files.
  final List<StorageAudioFile> evictionCandidates;

  const AdhanStorageInventory({
    required this.totalDirectoryBytes,
    required this.remoteCacheBytes,
    required this.userCustomBytes,
    required this.stagingTmpBytes,
    required this.unmanagedBytes,
    required this.reservedInFlightBytes,
    required this.remoteCacheQuotaBytes,
    required this.files,
    required this.activeAlarmPaths,
    required this.abandonedTmpFiles,
    required this.evictionCandidates,
  });

  /// Effective remote cache usage including active in-flight reservations.
  int get effectiveRemoteUsageBytes => remoteCacheBytes + reservedInFlightBytes;

  /// Remaining available quota for remote cache.
  int get availableRemoteQuotaBytes {
    final remaining = remoteCacheQuotaBytes - effectiveRemoteUsageBytes;
    return remaining > 0 ? remaining : 0;
  }

  /// Whether current effective remote usage exceeds the quota ceiling.
  bool get isQuotaExceeded => effectiveRemoteUsageBytes > remoteCacheQuotaBytes;

  /// Total bytes consumed by abandoned temporary files.
  int get abandonedTmpBytes =>
      abandonedTmpFiles.fold(0, (sum, f) => sum + f.byteLength);

  /// Checks if a candidate file at [relativePath] is safe for eviction.
  bool isCandidateSafeToEvict(String relativePath) {
    final norm = relativePath.replaceAll('\\', '/');
    return evictionCandidates.any((c) => c.relativePath == norm);
  }

  /// Creates an empty inventory representation for uninitialized or empty directories.
  factory AdhanStorageInventory.empty({
    int remoteCacheQuotaBytes = 150 * 1024 * 1024,
  }) {
    return AdhanStorageInventory(
      totalDirectoryBytes: 0,
      remoteCacheBytes: 0,
      userCustomBytes: 0,
      stagingTmpBytes: 0,
      unmanagedBytes: 0,
      reservedInFlightBytes: 0,
      remoteCacheQuotaBytes: remoteCacheQuotaBytes,
      files: const [],
      activeAlarmPaths: const {},
      abandonedTmpFiles: const [],
      evictionCandidates: const [],
    );
  }
}
