import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../entities/quran_download_queue.dart';
import '../entities/quran_download_queue_item.dart';
import '../entities/quran_download_queue_status.dart';

/// Pure domain repository contract for persisting and managing full-Quran download queues.
///
/// In accordance with QA.6 specifications:
/// - Single active queue invariant across the database.
/// - Deterministic sequence ordering (`position ASC` 0..113).
/// - Atomic operations for coordinated queue and item state mutations.
abstract class BaseAudioDownloadQueueRepository {
  /// Retrieves the currently active queue (`pending`, `running`, `paused`), or null if none.
  Future<Either<Failure, QuranDownloadQueue?>> getActiveQueue();

  /// Retrieves a specific queue by its unique ID, including all 114 items.
  Future<Either<Failure, QuranDownloadQueue?>> getQueueById(String queueId);

  /// Retrieves the latest queue associated with a specific reciter.
  Future<Either<Failure, QuranDownloadQueue?>> getLatestQueueForReciter(
    String reciterId,
  );

  /// Persists a newly created full-Quran queue and its 114 initial items.
  Future<Either<Failure, void>> createQueue(QuranDownloadQueue queue);

  /// Updates the aggregate status of a queue.
  Future<Either<Failure, void>> updateQueueStatus({
    required String queueId,
    required QuranDownloadQueueStatus status,
    DateTime? completedAt,
  });

  /// Updates aggregate download progress for a queue.
  Future<Either<Failure, void>> updateQueueProgress({
    required String queueId,
    required int completedItems,
    required int downloadedBytes,
    int? totalExpectedBytes,
  });

  /// Updates the status and progress of a single item within a queue.
  Future<Either<Failure, void>> updateQueueItemStatus({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueItemStatus status,
    int? downloadedBytes,
    String? lastError,
  });

  /// Atomically updates BOTH a queue item and its parent queue inside a single transaction.
  ///
  /// Critical for Pause, Error, and Cancellation transitions to eliminate partial states.
  Future<Either<Failure, void>> updateQueueAndItemStatusAtomic({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueStatus queueStatus,
    required QuranDownloadQueueItemStatus itemStatus,
    int? downloadedBytes,
    String? lastError,
  });

  /// Retrieves all 114 items for a queue, strictly ordered by `position ASC` (0..113).
  Future<Either<Failure, List<QuranDownloadQueueItem>>> getQueueItems(
    String queueId,
  );

  /// Resets all failed items in a queue to `pending` with incremented attempt counts.
  Future<Either<Failure, void>> retryFailedItems(String queueId);

  /// Permanently deletes a queue and cascades deletion of its 114 items.
  Future<Either<Failure, void>> deleteQueue(String queueId);
}
