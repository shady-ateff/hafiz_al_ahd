import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';

/// Contract for downloading, verifying, and promoting remote adhan audio files.
///
/// ## Core Lifecycle Invariant
/// A [AdhanCatalogEntry] is strictly metadata. It must never be used directly
/// as an alarm audio source until it passes through this service and is promoted
/// to a local [CustomAudioSource].
abstract class BaseAudioDownloadService {
  /// Returns the current state of a task for [entryId], or null if idle.
  AudioDownloadTask? getTask(String entryId);

  /// Returns the list of currently active download tasks (downloading, verifying, promoting).
  List<AudioDownloadTask> getActiveTasks() => const [];

  /// Returns the set of active temporary file prefixes currently being written.
  Set<String> getActiveTempPrefixes() => const {};

  /// Emits reactive state updates for the download task identified by [entryId].
  Stream<AudioDownloadTask> watchTask(String entryId);

  /// Checks if a valid, verified local audio file exists for [entryId].
  Future<bool> isAudioDownloaded(String entryId);

  /// Downloads, verifies, and promotes the audio file for [entry].
  ///
  /// ## Concurrency Policy
  /// Enforces single-download execution (mutex). If another download is actively
  /// streaming or verifying, this call returns [AudioDownloadConcurrencyFailure].
  ///
  /// ## Verification Contract
  /// 1. Download chunks to temporary file inside the same filesystem mount.
  /// 2. Validate downloaded byte count == [AdhanCatalogEntry.fileSizeBytes].
  /// 3. Validate byte count <= 30 MB (`kRemoteAudioMaxBytes`).
  /// 4. Calculate SHA-256 and assert exact match with [AdhanCatalogEntry.sha256].
  /// 5. Atomically promote file to private app storage.
  /// 6. Clean up temporary file immediately upon any failure.
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(
    AdhanCatalogEntry entry,
  );

  /// Cancels an in-flight download for [entryId], cleans up temporary files,
  /// and emits [DownloadStatus.cancelled].
  Future<void> cancelDownload(String entryId);

  /// Disposes all internal streams and cleans up any abandoned temporary files.
  Future<void> dispose();
}

