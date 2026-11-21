import 'dart:async';
import '../../domain/entities/quran_download_queue.dart';
import '../../domain/entities/quran_download_queue_item.dart';
import '../../domain/entities/quran_download_queue_progress.dart';
import '../../domain/entities/quran_download_queue_status.dart';
import '../../domain/entities/storage_preflight_result.dart';
import '../../domain/repositories/base_audio_download_queue_repository.dart';
import '../../domain/services/base_quran_audio_download_coordinator.dart';
import '../datasources/quran_audio_local_data_source.dart';
import 'quran_audio_download_service.dart';
import 'quran_audio_storage_service.dart';

/// Lightweight async mutex for serializing queue operations.
class _AsyncMutex {
  Future<void>? _last;

  Future<T> synchronized<T>(Future<T> Function() action) {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;

    return Future.sync(() async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      return await action();
    }).whenComplete(() {
      completer.complete();
    });
  }
}

/// Orchestrates full-Quran library downloads (114 Surahs sequentially) for a selected reciter.
///
/// Implements:
/// - Re-uses existing single-Surah download pipeline ([BaseQuranAudioDownloadService]).
/// - Strictly sequential execution (Surahs 1..114, 1 track at a time).
/// - Pre-checks existing completed Surahs and marks them `skipped` without network transfer.
/// - Atomic mutual exclusion via [BaseQuranAudioDownloadCoordinator].
/// - Idempotent, serialized queue operations (`pause`, `resume`, `cancel`, `retry`) via [_AsyncMutex].
class QuranAudioQueueService {
  final BaseAudioDownloadQueueRepository queueRepository;
  final BaseQuranAudioDownloadService downloadService;
  final BaseQuranAudioLocalDataSource localDataSource;
  final QuranAudioStorageService storageService;
  final BaseQuranAudioDownloadCoordinator coordinator;

  final _AsyncMutex _operationLock = _AsyncMutex();
  final StreamController<QuranDownloadQueueProgress> _progressController =
      StreamController<QuranDownloadQueueProgress>.broadcast();

  QuranDownloadQueueProgress? _currentProgress;
  DownloadReservationTicket? _activeQueueTicket;
  bool _isSchedulingHalted = false;
  int? _activeSurahNumber;

  QuranAudioQueueService({
    required this.queueRepository,
    required this.downloadService,
    required this.localDataSource,
    required this.storageService,
    required this.coordinator,
  });

  /// Real-time stream of full-Quran download progress telemetry.
  Stream<QuranDownloadQueueProgress> get progressStream => _progressController.stream;

  /// Current progress snapshot.
  QuranDownloadQueueProgress? get currentProgress => _currentProgress;

  /// Whether a queue is actively running in the worker.
  bool get isRunning => _currentProgress?.isRunning ?? false;

  void _emitProgress(QuranDownloadQueueProgress progress) {
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Inspects the database on app startup to recover any interrupted queue or running item.
  ///
  /// Invariant guarantees (Crash Recovery Matrix):
  /// 1. Runs QA.5 promotion journal recovery first via [storageService.reconcileStorageWithRegistry]
  ///    to ensure any in-flight atomic promotion is completed.
  /// 2. If an active queue had `status == running`, normalizes the queue to `paused`
  ///    to prevent unprompted cellular data transfers upon app restart.
  /// 3. Any item left with `status == running` is inspected:
  ///    - If verified complete on disk + DB registry, marked `completed`.
  ///    - If incomplete/partial, marked `paused` (preserving staging bytes for HTTP 206 resumption).
  /// 4. Aggregate metrics (`completedItems`, `downloadedBytes`) are deterministically recomputed.
  /// 5. If all 114 items are completed/skipped, transitions queue to `completed`.
  /// 6. Pre-populates [currentProgress] with the restored state and emits to [progressStream].
  Future<void> recoverInterruptedQueuesOnStartup() async {
    return _operationLock.synchronized(() async {
      // 1. First run QA.5 storage journal recovery
      try {
        await storageService.reconcileStorageWithRegistry(localDataSource);
      } catch (e) {
        // Storage reconciliation failures are logged but do not crash startup
      }

      // 2. Query for active queue
      final activeQueueResult = await queueRepository.getActiveQueue();
      final activeQueue = activeQueueResult.getOrElse(() => null);
      if (activeQueue == null) return;

      final itemsResult = await queueRepository.getQueueItems(activeQueue.id);
      final items = itemsResult.getOrElse(() => []);

      bool hadMutations = false;
      int completedCount = 0;
      int totalBytes = 0;

      for (final item in items) {
        if (item.status.isRunning) {
          // Check if it completed right before crash
          final record = await localDataSource.getDownloadRecord(
            item.surahNumber,
            activeQueue.reciterId,
          );
          final file = await storageService.resolveSurahFile(
            item.surahNumber,
            activeQueue.reciterId,
          );

          final bool isVerifiedOnDisk = record != null &&
              record.status.isCompleted &&
              record.transferIntegrityVerified &&
              await file.exists() &&
              await file.length() > 0 &&
              await file.length() == record.actualSizeBytes;

          if (isVerifiedOnDisk) {
            await queueRepository.updateQueueItemStatus(
              queueId: activeQueue.id,
              surahNumber: item.surahNumber,
              status: QuranDownloadQueueItemStatus.completed,
              downloadedBytes: record.actualSizeBytes,
            );
            completedCount++;
            totalBytes += record.actualSizeBytes;
          } else {
            // Reconcile interrupted running item to paused for range resumption
            final partialBytes = record?.actualSizeBytes ?? item.downloadedBytes;
            await queueRepository.updateQueueItemStatus(
              queueId: activeQueue.id,
              surahNumber: item.surahNumber,
              status: QuranDownloadQueueItemStatus.paused,
              downloadedBytes: partialBytes,
            );
            totalBytes += partialBytes;
          }
          hadMutations = true;
        } else {
          if (item.isCompletedOrSkipped) {
            completedCount++;
          }
          totalBytes += item.downloadedBytes;
        }
      }

      // If the queue was running at crash time, normalize to paused
      QuranDownloadQueueStatus newQueueStatus = activeQueue.status;
      if (activeQueue.status.isRunning) {
        newQueueStatus = QuranDownloadQueueStatus.paused;
        hadMutations = true;
      }

      // If all 114 items are completed or skipped, queue is completed
      if (completedCount == activeQueue.totalItems) {
        newQueueStatus = QuranDownloadQueueStatus.completed;
        hadMutations = true;
      }

      if (hadMutations) {
        await queueRepository.updateQueueStatus(
          queueId: activeQueue.id,
          status: newQueueStatus,
          completedAt: newQueueStatus.isCompleted ? DateTime.now() : null,
        );
        await queueRepository.updateQueueProgress(
          queueId: activeQueue.id,
          completedItems: completedCount,
          downloadedBytes: totalBytes,
        );
      }

      // Pre-populate and emit restored progress
      final ratio = activeQueue.totalExpectedBytes != null && activeQueue.totalExpectedBytes! > 0
          ? (totalBytes / activeQueue.totalExpectedBytes!).clamp(0.0, 1.0)
          : (activeQueue.totalItems > 0 ? (completedCount / activeQueue.totalItems).clamp(0.0, 1.0) : 0.0);

      _emitProgress(QuranDownloadQueueProgress(
        queueId: activeQueue.id,
        reciterId: activeQueue.reciterId,
        status: newQueueStatus,
        totalItems: activeQueue.totalItems,
        completedItems: completedCount,
        downloadedBytes: totalBytes,
        totalExpectedBytes: activeQueue.totalExpectedBytes,
        aggregateRatio: ratio,
      ));
    });
  }

  /// Performs storage preflight calculation before starting a full-Quran download queue.
  ///
  /// Invariants (Blueprint C6):
  /// 1. SAFETY_FLOOR_BYTES = 25 MB (fixed allocation for OS/WAL file buffers).
  /// 2. Staging buffer overhead is zero (in-place atomic rename).
  /// 3. If any pending (non-downloaded) Surah has null/zero expected bytes:
  ///    returns [StoragePreflightResult.indeterminate].
  /// 4. If available space is known and available < requiredBytes:
  ///    returns [StoragePreflightResult.insufficient].
  /// 5. Otherwise returns [StoragePreflightResult.sufficient].
  Future<StoragePreflightResult> checkStoragePreflight({
    required String reciterId,
    List<int?>? expectedSurahSizes,
  }) async {
    int pendingRequiredBytes = 0;
    bool hasIndeterminateSize = false;

    for (int surahNum = 1; surahNum <= 114; surahNum++) {
      final record = await localDataSource.getDownloadRecord(surahNum, reciterId);
      final file = await storageService.resolveSurahFile(surahNum, reciterId);

      final bool isAlreadyDownloaded = record != null &&
          record.status.isCompleted &&
          record.transferIntegrityVerified &&
          await file.exists() &&
          await file.length() > 0;

      if (!isAlreadyDownloaded) {
        final expectedSize = (expectedSurahSizes != null &&
                expectedSurahSizes.length == 114)
            ? expectedSurahSizes[surahNum - 1]
            : null;

        if (expectedSize == null || expectedSize <= 0) {
          hasIndeterminateSize = true;
        } else {
          pendingRequiredBytes += expectedSize;
        }
      }
    }

    final availableBytes = await storageService.getAvailableDiskSpace();

    if (hasIndeterminateSize) {
      return StoragePreflightResult.indeterminate(
        availableBytes: availableBytes,
      );
    }

    final totalRequiredBytes =
        pendingRequiredBytes + QuranAudioStorageService.kSafetyFloorBytes;

    if (availableBytes != null && availableBytes < totalRequiredBytes) {
      return StoragePreflightResult.insufficient(
        requiredBytes: totalRequiredBytes,
        availableBytes: availableBytes,
      );
    }

    return StoragePreflightResult.sufficient(
      requiredBytes: totalRequiredBytes,
      availableBytes: availableBytes,
    );
  }

  /// Initiates a new full-Quran download queue for [reciterId].
  ///
  /// Reconciles already completed Surahs in QA.5 and marks them `skipped`.
  Future<QuranDownloadQueue> startQueue({
    required String reciterId,
    required FutureOr<String> Function(int surahNumber) urlBuilder,
    List<int>? expectedSurahSizes,
  }) async {
    return _operationLock.synchronized(() async {
      // 1. Guard against concurrent active queues
      final activeQueueResult = await queueRepository.getActiveQueue();
      final existingActive = activeQueueResult.getOrElse(() => null);
      if (existingActive != null) {
        throw StateError(
          'Cannot start full-Quran queue: An active queue (${existingActive.id}) already exists.',
        );
      }

      // 2. Build 114 initial items with verified-skipped pre-check
      final now = DateTime.now();
      final queueId = 'queue_${reciterId}_${now.millisecondsSinceEpoch}';
      final List<QuranDownloadQueueItem> items = [];
      int preCompletedCount = 0;
      int preDownloadedBytes = 0;

      for (int i = 0; i < 114; i++) {
        final surahNum = i + 1;
        final expectedBytes =
            (expectedSurahSizes != null && expectedSurahSizes.length == 114)
                ? expectedSurahSizes[i]
                : null;

        // Check if verified completed in QA.5 registry
        final existingRecord =
            await localDataSource.getDownloadRecord(surahNum, reciterId);
        final file = await storageService.resolveSurahFile(surahNum, reciterId);

        final bool isAlreadyVerified = existingRecord != null &&
            existingRecord.status.isCompleted &&
            existingRecord.transferIntegrityVerified &&
            await file.exists() &&
            await file.length() > 0;

        if (isAlreadyVerified) {
          preCompletedCount++;
          preDownloadedBytes += existingRecord.actualSizeBytes;
          items.add(QuranDownloadQueueItem(
            id: '${queueId}_$surahNum',
            queueId: queueId,
            surahNumber: surahNum,
            position: i,
            status: QuranDownloadQueueItemStatus.skipped,
            expectedBytes: existingRecord.actualSizeBytes,
            downloadedBytes: existingRecord.actualSizeBytes,
            attemptCount: 0,
            createdAt: now,
            updatedAt: now,
          ));
        } else {
          items.add(QuranDownloadQueueItem(
            id: '${queueId}_$surahNum',
            queueId: queueId,
            surahNumber: surahNum,
            position: i,
            status: QuranDownloadQueueItemStatus.pending,
            expectedBytes: expectedBytes,
            downloadedBytes: 0,
            attemptCount: 0,
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      final int? totalExpectedBytes = (expectedSurahSizes != null &&
              expectedSurahSizes.length == 114 &&
              !expectedSurahSizes.contains(-1))
          ? expectedSurahSizes.fold<int>(0, (sum, b) => sum + b)
          : null;

      final queue = QuranDownloadQueue(
        id: queueId,
        reciterId: reciterId,
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: preCompletedCount,
        totalExpectedBytes: totalExpectedBytes,
        downloadedBytes: preDownloadedBytes,
        createdAt: now,
        updatedAt: now,
        items: items,
      );

      // 3. Persist queue to SQLite
      final createResult = await queueRepository.createQueue(queue);
      createResult.fold(
        (failure) => throw StateError('Failed to create queue in database: ${failure.message}'),
        (_) => null,
      );

      // 4. Acquire coordinator ticket
      _activeQueueTicket = await coordinator.reserveQueue(
        queueId: queueId,
        reciterId: reciterId,
      );

      _isSchedulingHalted = false;

      // 5. Emit initial progress
      _emitProgress(QuranDownloadQueueProgress(
        queueId: queueId,
        reciterId: reciterId,
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: preCompletedCount,
        downloadedBytes: preDownloadedBytes,
        totalExpectedBytes: totalExpectedBytes,
        aggregateRatio: queue.aggregateRatio,
      ));

      // 6. Spawn sequential worker in background
      unawaited(_runWorker(queueId, reciterId, urlBuilder));

      return queue;
    });
  }

  /// Pauses the running queue, halting active transfer and preserving staging bytes.
  Future<void> pauseQueue(String queueId) async {
    return _operationLock.synchronized(() async {
      final queueResult = await queueRepository.getQueueById(queueId);
      final queue = queueResult.getOrElse(() => null);
      if (queue == null || queue.status.isPaused || queue.status.isTerminal) {
        return; // Idempotent no-op
      }

      _isSchedulingHalted = true;
      final activeSurah = _activeSurahNumber;

      if (activeSurah != null) {
        await downloadService.pauseDownload(activeSurah, queue.reciterId);
        await queueRepository.updateQueueAndItemStatusAtomic(
          queueId: queueId,
          surahNumber: activeSurah,
          queueStatus: QuranDownloadQueueStatus.paused,
          itemStatus: QuranDownloadQueueItemStatus.paused,
        );
      } else {
        await queueRepository.updateQueueStatus(
          queueId: queueId,
          status: QuranDownloadQueueStatus.paused,
        );
      }

      _activeQueueTicket?.dispose();
      _activeQueueTicket = null;
      _activeSurahNumber = null;

      _emitProgress(QuranDownloadQueueProgress(
        queueId: queueId,
        reciterId: queue.reciterId,
        status: QuranDownloadQueueStatus.paused,
        totalItems: queue.totalItems,
        completedItems: queue.completedItems,
        downloadedBytes: queue.downloadedBytes,
        totalExpectedBytes: queue.totalExpectedBytes,
        aggregateRatio: queue.aggregateRatio,
      ));
    });
  }

  /// Resumes a paused full-Quran queue from its next pending item.
  Future<void> resumeQueue({
    required String queueId,
    required FutureOr<String> Function(int surahNumber) urlBuilder,
  }) async {
    return _operationLock.synchronized(() async {
      final queueResult = await queueRepository.getQueueById(queueId);
      final queue = queueResult.getOrElse(() => null);
      if (queue == null || queue.status.isRunning || queue.status.isTerminal) {
        return; // Idempotent no-op
      }

      // Acquire coordinator reservation
      _activeQueueTicket = await coordinator.reserveQueue(
        queueId: queueId,
        reciterId: queue.reciterId,
      );

      _isSchedulingHalted = false;
      await queueRepository.updateQueueStatus(
        queueId: queueId,
        status: QuranDownloadQueueStatus.running,
      );

      _emitProgress(QuranDownloadQueueProgress(
        queueId: queueId,
        reciterId: queue.reciterId,
        status: QuranDownloadQueueStatus.running,
        totalItems: queue.totalItems,
        completedItems: queue.completedItems,
        downloadedBytes: queue.downloadedBytes,
        totalExpectedBytes: queue.totalExpectedBytes,
        aggregateRatio: queue.aggregateRatio,
      ));

      unawaited(_runWorker(queueId, queue.reciterId, urlBuilder));
    });
  }

  /// Cancels the full-Quran queue, aborting active transfer and cleaning resources.
  Future<void> cancelQueue(String queueId) async {
    return _operationLock.synchronized(() async {
      final queueResult = await queueRepository.getQueueById(queueId);
      final queue = queueResult.getOrElse(() => null);
      if (queue == null || queue.status.isCancelled) {
        return; // Idempotent no-op
      }

      _isSchedulingHalted = true;
      final activeSurah = _activeSurahNumber;

      // 1. Record cancellation intent in DB
      await queueRepository.updateQueueStatus(
        queueId: queueId,
        status: QuranDownloadQueueStatus.cancelled,
      );

      // 2. Abort active single-Surah download
      if (activeSurah != null) {
        await downloadService.cancelDownload(activeSurah, queue.reciterId);
        await queueRepository.updateQueueItemStatus(
          queueId: queueId,
          surahNumber: activeSurah,
          status: QuranDownloadQueueItemStatus.cancelled,
        );
      }

      // 3. Mark any remaining pending, paused, or running items as cancelled
      for (final item in queue.items) {
        if (item.status.isPending || item.status.isPaused || item.status.isRunning) {
          await queueRepository.updateQueueItemStatus(
            queueId: queueId,
            surahNumber: item.surahNumber,
            status: QuranDownloadQueueItemStatus.cancelled,
          );
        }
      }

      _activeQueueTicket?.dispose();
      _activeQueueTicket = null;
      _activeSurahNumber = null;

      _emitProgress(QuranDownloadQueueProgress(
        queueId: queueId,
        reciterId: queue.reciterId,
        status: QuranDownloadQueueStatus.cancelled,
        totalItems: queue.totalItems,
        completedItems: queue.completedItems,
        downloadedBytes: queue.downloadedBytes,
        totalExpectedBytes: queue.totalExpectedBytes,
        aggregateRatio: queue.aggregateRatio,
      ));
    });
  }

  /// Retries all failed items in the queue and resumes execution.
  Future<void> retryQueue({
    required String queueId,
    required FutureOr<String> Function(int surahNumber) urlBuilder,
  }) async {
    return _operationLock.synchronized(() async {
      final queueResult = await queueRepository.getQueueById(queueId);
      final queue = queueResult.getOrElse(() => null);
      if (queue == null) return;

      await queueRepository.retryFailedItems(queueId);

      _activeQueueTicket ??= await coordinator.reserveQueue(
        queueId: queueId,
        reciterId: queue.reciterId,
      );

      _isSchedulingHalted = false;

      _emitProgress(QuranDownloadQueueProgress(
        queueId: queueId,
        reciterId: queue.reciterId,
        status: QuranDownloadQueueStatus.running,
        totalItems: queue.totalItems,
        completedItems: queue.completedItems,
        downloadedBytes: queue.downloadedBytes,
        totalExpectedBytes: queue.totalExpectedBytes,
        aggregateRatio: queue.aggregateRatio,
      ));

      unawaited(_runWorker(queueId, queue.reciterId, urlBuilder));
    });
  }

  /// Sequential worker processing one Surah track at a time from Surah 1 to 114.
  Future<void> _runWorker(
    String queueId,
    String reciterId,
    FutureOr<String> Function(int surahNumber) urlBuilder,
  ) async {
    while (!_isSchedulingHalted) {
      final queueResult = await queueRepository.getQueueById(queueId);
      final queue = queueResult.getOrElse(() => null);
      if (queue == null || _isSchedulingHalted || !queue.status.isRunning) {
        break;
      }

      // Find next item to process in position order
      final item = queue.items.cast<QuranDownloadQueueItem?>().firstWhere(
            (i) => i != null && (i.status.isPending || i.status.isPaused),
            orElse: () => null,
          );

      if (item == null) {
        // All items have been processed! Check completion condition
        if (queue.isFullyCompleted) {
          final now = DateTime.now();
          await queueRepository.updateQueueStatus(
            queueId: queueId,
            status: QuranDownloadQueueStatus.completed,
            completedAt: now,
          );
          _activeQueueTicket?.dispose();
          _activeQueueTicket = null;
          _activeSurahNumber = null;

          _emitProgress(QuranDownloadQueueProgress(
            queueId: queueId,
            reciterId: reciterId,
            status: QuranDownloadQueueStatus.completed,
            totalItems: 114,
            completedItems: 114,
            downloadedBytes: queue.downloadedBytes,
            totalExpectedBytes: queue.totalExpectedBytes,
            aggregateRatio: 1.0,
          ));
        }
        break;
      }

      // Runtime disk space safety floor check (Blueprint C6)
      final availableDisk = await storageService.getAvailableDiskSpace();
      if (availableDisk != null &&
          availableDisk < QuranAudioStorageService.kSafetyFloorBytes) {
        const errorMsg =
            'المساحة التخزينية المتاحة أقل من الحد الأدنى الآمن (25 ميجابايت)';
        await queueRepository.updateQueueItemStatus(
          queueId: queueId,
          surahNumber: item.surahNumber,
          status: QuranDownloadQueueItemStatus.failed,
          lastError: errorMsg,
        );
        await queueRepository.updateQueueStatus(
          queueId: queueId,
          status: QuranDownloadQueueStatus.failed,
        );
        _activeQueueTicket?.dispose();
        _activeQueueTicket = null;
        _activeSurahNumber = null;

        _emitProgress(QuranDownloadQueueProgress(
          queueId: queueId,
          reciterId: reciterId,
          status: QuranDownloadQueueStatus.failed,
          totalItems: 114,
          completedItems: queue.completedItems,
          downloadedBytes: queue.downloadedBytes,
          totalExpectedBytes: queue.totalExpectedBytes,
          aggregateRatio: queue.aggregateRatio,
          lastError: errorMsg,
        ));
        break;
      }

      // Process this item
      _activeSurahNumber = item.surahNumber;

      // Mark item as running
      await queueRepository.updateQueueItemStatus(
        queueId: queueId,
        surahNumber: item.surahNumber,
        status: QuranDownloadQueueItemStatus.running,
      );

      final audioUrl = await urlBuilder(item.surahNumber);

      final result = await downloadService.downloadSurahAndWait(
        surahNumber: item.surahNumber,
        reciterId: reciterId,
        audioUrl: audioUrl,
        expectedTotalBytes: item.expectedBytes,
        skipCoordinatorReservation: true, // We already hold queue reservation ticket!
        onProgress: (itemProgress) {
          if (!_isSchedulingHalted) {
            _emitProgress(QuranDownloadQueueProgress(
              queueId: queueId,
              reciterId: reciterId,
              status: QuranDownloadQueueStatus.running,
              totalItems: 114,
              completedItems: queue.completedItems,
              activeSurahNumber: item.surahNumber,
              activeSurahPosition: item.position,
              activeItemProgress: itemProgress,
              downloadedBytes: queue.downloadedBytes + itemProgress.downloadedBytes,
              totalExpectedBytes: queue.totalExpectedBytes,
              aggregateRatio: queue.aggregateRatio,
            ));
          }
        },
      );

      _activeSurahNumber = null;
      if (_isSchedulingHalted) break;

      if (result.isCompleted) {
        await queueRepository.updateQueueItemStatus(
          queueId: queueId,
          surahNumber: item.surahNumber,
          status: QuranDownloadQueueItemStatus.completed,
          downloadedBytes: result.totalBytes,
        );

        // Recalculate totals
        final updatedItemsResult = await queueRepository.getQueueItems(queueId);
        final updatedItems = updatedItemsResult.getOrElse(() => []);
        final completedCount =
            updatedItems.where((i) => i.isCompletedOrSkipped).length;
        final totalBytes =
            updatedItems.fold<int>(0, (sum, i) => sum + i.downloadedBytes);

        await queueRepository.updateQueueProgress(
          queueId: queueId,
          completedItems: completedCount,
          downloadedBytes: totalBytes,
        );
      } else if (result.isFailed) {
        await queueRepository.updateQueueItemStatus(
          queueId: queueId,
          surahNumber: item.surahNumber,
          status: QuranDownloadQueueItemStatus.failed,
          lastError: result.errorMessage,
          downloadedBytes: result.downloadedBytes,
        );

        // Halt queue on unrecoverable item failure
        await queueRepository.updateQueueStatus(
          queueId: queueId,
          status: QuranDownloadQueueStatus.failed,
        );

        _activeQueueTicket?.dispose();
        _activeQueueTicket = null;

        _emitProgress(QuranDownloadQueueProgress(
          queueId: queueId,
          reciterId: reciterId,
          status: QuranDownloadQueueStatus.failed,
          totalItems: 114,
          completedItems: queue.completedItems,
          downloadedBytes: queue.downloadedBytes,
          totalExpectedBytes: queue.totalExpectedBytes,
          aggregateRatio: queue.aggregateRatio,
          lastError: result.errorMessage,
        ));
        break;
      } else if (result.isPaused || result.isCancelled) {
        break;
      }
    }
  }

  void dispose() {
    _isSchedulingHalted = true;
    _activeQueueTicket?.dispose();
    _activeQueueTicket = null;
    _progressController.close();
  }
}
