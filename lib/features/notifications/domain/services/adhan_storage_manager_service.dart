import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';

/// Contract for inspecting application audio storage, accounting for remote cache quota,
/// detecting abandoned temporary downloads, identifying safe eviction candidates,
/// and executing safe, atomic, alarm-aware file deletions.
///
/// ## Immutable Architectural Rules:
/// 1. **Atomic Just-In-Time Revalidation:** Every delete operation re-verifies active alarm
///    references at the exact millisecond of execution. Never rely on stale UI snapshots.
/// 2. **Active Alarm Lock:** Any file referenced in active prayer alarm settings is strictly
///    protected and can NEVER be deleted.
/// 3. **User Audio Protection:** User-imported custom audio (`custom_*`) can only be deleted
///    via explicit user action ([isUserExplicit] = true) when NOT assigned to any prayer.
/// 4. **Unmanaged Protection:** Files classified as [StorageFileClassification.unmanaged]
///    are strictly rejected from automated deletion.
/// 5. **Safe Cleanup:** Cleanup sweeps exclusively target abandoned `.tmp` files not bound
///    to any active download task.
abstract class BaseAdhanStorageManagerService {
  /// Scans the `adhan_sounds` directory, correlates with active prayer alarm references,
  /// accounts for in-flight download reservations, and produces a complete storage inventory.
  Future<AdhanStorageInventory> inspectStorage();

  /// Returns the set of normalized relative paths currently assigned to any active prayer alarm.
  Future<Set<String>> getActiveAlarmAudioPaths();

  /// Checks if downloading an entry of [requiredBytes] would exceed the remote cache quota.
  Future<QuotaCheckResult> checkQuota({required int requiredBytes});

  /// Identifies abandoned temporary files in `.tmp/` older than [ageThreshold] (default 60 min)
  /// that are not registered in active download tasks.
  Future<List<StorageAudioFile>> getAbandonedTmpFiles({
    Duration ageThreshold = const Duration(minutes: 60),
  });

  /// Returns safe eviction candidates sorted by eviction priority (oldest modified first).
  /// Strictly excludes active alarm files, user custom audio, and unmanaged files.
  Future<List<StorageAudioFile>> getSafeEvictionCandidates();

  /// Safely deletes a single physical audio file identified by [relativePath].
  ///
  /// ## Mandatory Re-validations at Delete Execution:
  /// - Path traversal & canonical root validation.
  /// - Live query of [BasePrayerAlarmConfigLocalDataSource] (rejection if active in any prayer).
  /// - Active download registry check (rejection if active).
  /// - Classification validation (userCustom requires [isUserExplicit] = true; unmanaged rejected).
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(
    String relativePath, {
    bool isUserExplicit = false,
  });

  /// Performs a garbage collection sweep of abandoned files inside `adhan_sounds/.tmp/`.
  /// Strictly skips any `.tmp` file matching active download task prefixes or newer than [ageThreshold].
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({
    Duration ageThreshold = const Duration(minutes: 60),
  });
}

