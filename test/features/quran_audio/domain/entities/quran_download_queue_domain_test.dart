import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_item.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_status.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/single_surah_download_result.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/services/base_quran_audio_download_coordinator.dart';

void main() {
  group('QA.6 Phase 6.2 - QuranDownloadQueueStatus & ItemStatus Domain Tests', () {
    test('QuranDownloadQueueStatus isActive matches SQLite partial unique index', () {
      expect(QuranDownloadQueueStatus.pending.isActive, isTrue);
      expect(QuranDownloadQueueStatus.running.isActive, isTrue);
      expect(QuranDownloadQueueStatus.paused.isActive, isTrue);

      expect(QuranDownloadQueueStatus.completed.isActive, isFalse);
      expect(QuranDownloadQueueStatus.failed.isActive, isFalse);
      expect(QuranDownloadQueueStatus.cancelled.isActive, isFalse);
    });

    test('QuranDownloadQueueStatus isTerminal and isResumable', () {
      expect(QuranDownloadQueueStatus.completed.isTerminal, isTrue);
      expect(QuranDownloadQueueStatus.failed.isTerminal, isTrue);
      expect(QuranDownloadQueueStatus.cancelled.isTerminal, isTrue);
      expect(QuranDownloadQueueStatus.running.isTerminal, isFalse);

      expect(QuranDownloadQueueStatus.paused.isResumable, isTrue);
      expect(QuranDownloadQueueStatus.failed.isResumable, isTrue);
      expect(QuranDownloadQueueStatus.completed.isResumable, isFalse);
    });

    test('QuranDownloadQueueStatus state transitions follow authoritative rules', () {
      // Pending
      expect(QuranDownloadQueueStatus.pending.canTransitionTo(QuranDownloadQueueStatus.running), isTrue);
      expect(QuranDownloadQueueStatus.pending.canTransitionTo(QuranDownloadQueueStatus.paused), isTrue);
      expect(QuranDownloadQueueStatus.pending.canTransitionTo(QuranDownloadQueueStatus.cancelled), isTrue);
      expect(QuranDownloadQueueStatus.pending.canTransitionTo(QuranDownloadQueueStatus.completed), isFalse);

      // Running
      expect(QuranDownloadQueueStatus.running.canTransitionTo(QuranDownloadQueueStatus.paused), isTrue);
      expect(QuranDownloadQueueStatus.running.canTransitionTo(QuranDownloadQueueStatus.completed), isTrue);
      expect(QuranDownloadQueueStatus.running.canTransitionTo(QuranDownloadQueueStatus.failed), isTrue);
      expect(QuranDownloadQueueStatus.running.canTransitionTo(QuranDownloadQueueStatus.cancelled), isTrue);

      // Paused
      expect(QuranDownloadQueueStatus.paused.canTransitionTo(QuranDownloadQueueStatus.running), isTrue);
      expect(QuranDownloadQueueStatus.paused.canTransitionTo(QuranDownloadQueueStatus.cancelled), isTrue);
      expect(QuranDownloadQueueStatus.paused.canTransitionTo(QuranDownloadQueueStatus.completed), isFalse);

      // Failed (Retry or Cancel)
      expect(QuranDownloadQueueStatus.failed.canTransitionTo(QuranDownloadQueueStatus.running), isTrue);
      expect(QuranDownloadQueueStatus.failed.canTransitionTo(QuranDownloadQueueStatus.cancelled), isTrue);

      // Terminal (completed, cancelled)
      expect(QuranDownloadQueueStatus.completed.canTransitionTo(QuranDownloadQueueStatus.running), isFalse);
      expect(QuranDownloadQueueStatus.cancelled.canTransitionTo(QuranDownloadQueueStatus.running), isFalse);

      // Idempotency
      expect(QuranDownloadQueueStatus.running.canTransitionTo(QuranDownloadQueueStatus.running), isTrue);
    });

    test('QuranDownloadQueueStatus string serialization and deserialization', () {
      for (final status in QuranDownloadQueueStatus.values) {
        final str = status.toDbString();
        expect(QuranDownloadQueueStatus.fromString(str), equals(status));
      }
      expect(
        () => QuranDownloadQueueStatus.fromString('invalid_status'),
        throwsArgumentError,
      );
    });

    test('QuranDownloadQueueItemStatus satisfies completion and terminal invariants', () {
      expect(QuranDownloadQueueItemStatus.completed.isCompletedOrSkipped, isTrue);
      expect(QuranDownloadQueueItemStatus.skipped.isCompletedOrSkipped, isTrue);
      expect(QuranDownloadQueueItemStatus.running.isCompletedOrSkipped, isFalse);

      expect(QuranDownloadQueueItemStatus.completed.isTerminal, isTrue);
      expect(QuranDownloadQueueItemStatus.failed.isTerminal, isTrue);
      expect(QuranDownloadQueueItemStatus.cancelled.isTerminal, isTrue);
      expect(QuranDownloadQueueItemStatus.skipped.isTerminal, isTrue);
      expect(QuranDownloadQueueItemStatus.running.isTerminal, isFalse);
    });

    test('QuranDownloadQueueItemStatus transitions follow queue lifecycle', () {
      expect(QuranDownloadQueueItemStatus.pending.canTransitionTo(QuranDownloadQueueItemStatus.running), isTrue);
      expect(QuranDownloadQueueItemStatus.pending.canTransitionTo(QuranDownloadQueueItemStatus.skipped), isTrue);
      expect(QuranDownloadQueueItemStatus.running.canTransitionTo(QuranDownloadQueueItemStatus.completed), isTrue);
      expect(QuranDownloadQueueItemStatus.running.canTransitionTo(QuranDownloadQueueItemStatus.paused), isTrue);
      expect(QuranDownloadQueueItemStatus.running.canTransitionTo(QuranDownloadQueueItemStatus.failed), isTrue);

      // Retry from failed -> pending
      expect(QuranDownloadQueueItemStatus.failed.canTransitionTo(QuranDownloadQueueItemStatus.pending), isTrue);
      expect(QuranDownloadQueueItemStatus.failed.canTransitionTo(QuranDownloadQueueItemStatus.cancelled), isTrue);

      // Completed is strictly terminal
      expect(QuranDownloadQueueItemStatus.completed.canTransitionTo(QuranDownloadQueueItemStatus.pending), isFalse);
      expect(QuranDownloadQueueItemStatus.skipped.canTransitionTo(QuranDownloadQueueItemStatus.running), isFalse);
    });

    test('QuranDownloadQueueItemStatus string serialization and deserialization', () {
      for (final status in QuranDownloadQueueItemStatus.values) {
        final str = status.toDbString();
        expect(QuranDownloadQueueItemStatus.fromString(str), equals(status));
      }
      expect(
        () => QuranDownloadQueueItemStatus.fromString('corrupt_item_status'),
        throwsArgumentError,
      );
    });
  });

  group('QA.6 Phase 6.2 - SingleSurahDownloadResult Domain Tests', () {
    test('SingleSurahDownloadResult completed factory initializes correctly', () {
      final res = SingleSurahDownloadResult.completed(
        surahNumber: 1,
        reciterId: '7',
        filePath: '/data/quran_audio/7/001.mp3',
        totalBytes: 524288,
        sha256: 'abc123hash',
      );

      expect(res.isCompleted, isTrue);
      expect(res.isFailed, isFalse);
      expect(res.isPaused, isFalse);
      expect(res.isCancelled, isFalse);
      expect(res.surahNumber, equals(1));
      expect(res.reciterId, equals('7'));
      expect(res.filePath, equals('/data/quran_audio/7/001.mp3'));
      expect(res.totalBytes, equals(524288));
      expect(res.downloadedBytes, equals(524288));
      expect(res.sha256, equals('abc123hash'));
      expect(res.errorMessage, isNull);
    });

    test('SingleSurahDownloadResult failed factory initializes correctly', () {
      final res = SingleSurahDownloadResult.failed(
        surahNumber: 2,
        reciterId: '7',
        errorMessage: 'Network timeout',
        downloadedBytes: 1024,
      );

      expect(res.isCompleted, isFalse);
      expect(res.isFailed, isTrue);
      expect(res.isPaused, isFalse);
      expect(res.isCancelled, isFalse);
      expect(res.errorMessage, equals('Network timeout'));
      expect(res.downloadedBytes, equals(1024));
    });

    test('SingleSurahDownloadResult paused factory initializes correctly', () {
      final res = SingleSurahDownloadResult.paused(
        surahNumber: 3,
        reciterId: '7',
        downloadedBytes: 2048,
      );

      expect(res.isPaused, isTrue);
      expect(res.isCompleted, isFalse);
      expect(res.downloadedBytes, equals(2048));
    });

    test('SingleSurahDownloadResult cancelled factory initializes correctly', () {
      final res = SingleSurahDownloadResult.cancelled(
        surahNumber: 4,
        reciterId: '7',
      );

      expect(res.isCancelled, isTrue);
      expect(res.isCompleted, isFalse);
    });

    test('SingleSurahDownloadResult Equatable value equality', () {
      final res1 = SingleSurahDownloadResult.completed(
        surahNumber: 1,
        reciterId: '7',
        filePath: '/path/001.mp3',
        totalBytes: 100,
        sha256: 'hash1',
      );
      final res2 = SingleSurahDownloadResult.completed(
        surahNumber: 1,
        reciterId: '7',
        filePath: '/path/001.mp3',
        totalBytes: 100,
        sha256: 'hash1',
      );

      expect(res1, equals(res2));
    });
  });

  group('QA.6 Phase 6.2 - QuranDownloadQueueItem Domain Tests', () {
    final now = DateTime.now();

    test('valid instantiation with correct bounds', () {
      final item = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.pending,
        expectedBytes: 1000,
        downloadedBytes: 0,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      );

      expect(item.surahNumber, equals(1));
      expect(item.position, equals(0));
      expect(item.status, equals(QuranDownloadQueueItemStatus.pending));
      expect(item.progressRatio, equals(0.0));
      expect(item.isCompletedOrSkipped, isFalse);
    });

    test('throws ArgumentError on invalid surahNumber (< 1 or > 114)', () {
      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_0',
          queueId: 'q1',
          surahNumber: 0,
          position: 0,
          status: QuranDownloadQueueItemStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_115',
          queueId: 'q1',
          surahNumber: 115,
          position: 0,
          status: QuranDownloadQueueItemStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on invalid position (< 0 or > 113)', () {
      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_1',
          queueId: 'q1',
          surahNumber: 1,
          position: -1,
          status: QuranDownloadQueueItemStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_1',
          queueId: 'q1',
          surahNumber: 1,
          position: 114,
          status: QuranDownloadQueueItemStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on negative numbers', () {
      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_1',
          queueId: 'q1',
          surahNumber: 1,
          position: 0,
          status: QuranDownloadQueueItemStatus.pending,
          downloadedBytes: -1,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => QuranDownloadQueueItem(
          id: 'q1_1',
          queueId: 'q1',
          surahNumber: 1,
          position: 0,
          status: QuranDownloadQueueItemStatus.pending,
          attemptCount: -1,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('progressRatio calculates determinate, indeterminate, and completed states', () {
      final runningDeterminate = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.running,
        expectedBytes: 1000,
        downloadedBytes: 250,
        createdAt: now,
        updatedAt: now,
      );
      expect(runningDeterminate.progressRatio, equals(0.25));

      final runningIndeterminate = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.running,
        expectedBytes: null,
        downloadedBytes: 250,
        createdAt: now,
        updatedAt: now,
      );
      expect(runningIndeterminate.progressRatio, isNull);

      final completedItem = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.completed,
        expectedBytes: null,
        downloadedBytes: 250,
        createdAt: now,
        updatedAt: now,
      );
      expect(completedItem.progressRatio, equals(1.0));

      final skippedItem = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.skipped,
        createdAt: now,
        updatedAt: now,
      );
      expect(skippedItem.progressRatio, equals(1.0));
      expect(skippedItem.isCompletedOrSkipped, isTrue);
    });

    test('copyWith updates fields correctly', () {
      final item = QuranDownloadQueueItem(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      final updated = item.copyWith(
        status: QuranDownloadQueueItemStatus.running,
        downloadedBytes: 500,
        attemptCount: 1,
      );

      expect(updated.status, equals(QuranDownloadQueueItemStatus.running));
      expect(updated.downloadedBytes, equals(500));
      expect(updated.attemptCount, equals(1));
      expect(updated.surahNumber, equals(1));
      expect(updated.position, equals(0));
    });
  });

  group('QA.6 Phase 6.2 - QuranDownloadQueue Domain Tests', () {
    final now = DateTime.now();

    List<QuranDownloadQueueItem> create114Items(String queueId, {QuranDownloadQueueItemStatus defaultStatus = QuranDownloadQueueItemStatus.pending}) {
      return List.generate(114, (index) {
        return QuranDownloadQueueItem(
          id: '${queueId}_${index + 1}',
          queueId: queueId,
          surahNumber: index + 1,
          position: index,
          status: defaultStatus,
          createdAt: now,
          updatedAt: now,
        );
      });
    }

    test('valid instantiation with 114 items and invariant checks', () {
      final items = create114Items('q1');
      final queue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.pending,
        totalItems: 114,
        completedItems: 0,
        downloadedBytes: 0,
        createdAt: now,
        updatedAt: now,
        items: items,
      );

      expect(queue.id, equals('q1'));
      expect(queue.reciterId, equals('7'));
      expect(queue.totalItems, equals(114));
      expect(queue.completedItems, equals(0));
      expect(queue.isActive, isTrue);
      expect(queue.isTerminal, isFalse);
      expect(queue.isFullyCompleted, isFalse);
      expect(queue.nextPendingItem?.surahNumber, equals(1));
      expect(queue.activeItem, isNull);
    });

    test('throws ArgumentError if totalItems != 114', () {
      expect(
        () => QuranDownloadQueue(
          id: 'q1',
          reciterId: '7',
          status: QuranDownloadQueueStatus.pending,
          totalItems: 100,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError if completedItems < 0 or > 114', () {
      expect(
        () => QuranDownloadQueue(
          id: 'q1',
          reciterId: '7',
          status: QuranDownloadQueueStatus.pending,
          completedItems: -1,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => QuranDownloadQueue(
          id: 'q1',
          reciterId: '7',
          status: QuranDownloadQueueStatus.pending,
          completedItems: 115,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError if items list is not empty and length != 114', () {
      expect(
        () => QuranDownloadQueue(
          id: 'q1',
          reciterId: '7',
          status: QuranDownloadQueueStatus.pending,
          createdAt: now,
          updatedAt: now,
          items: [
            QuranDownloadQueueItem(
              id: 'q1_1',
              queueId: 'q1',
              surahNumber: 1,
              position: 0,
              status: QuranDownloadQueueItemStatus.pending,
              createdAt: now,
              updatedAt: now,
            )
          ],
        ),
        throwsArgumentError,
      );
    });

    test('isFullyCompleted invariant requires completedItems == 114 and all items completed/skipped', () {
      // 100 completed, 14 skipped = 114 satisfied
      final mixedItems = List.generate(114, (index) {
        return QuranDownloadQueueItem(
          id: 'q1_${index + 1}',
          queueId: 'q1',
          surahNumber: index + 1,
          position: index,
          status: index < 100
              ? QuranDownloadQueueItemStatus.completed
              : QuranDownloadQueueItemStatus.skipped,
          createdAt: now,
          updatedAt: now,
        );
      });

      final completedQueue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.completed,
        completedItems: 114,
        createdAt: now,
        updatedAt: now,
        items: mixedItems,
      );

      expect(completedQueue.isFullyCompleted, isTrue);
      expect(completedQueue.aggregateRatio, equals(1.0));
      expect(completedQueue.isTerminal, isTrue);
      expect(completedQueue.isActive, isFalse);

      // Incomplete item breaks isFullyCompleted even if completedItems was set to 114
      final brokenItems = List<QuranDownloadQueueItem>.from(mixedItems);
      brokenItems[113] = brokenItems[113].copyWith(status: QuranDownloadQueueItemStatus.failed);

      final invalidQueue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        completedItems: 114,
        createdAt: now,
        updatedAt: now,
        items: brokenItems,
      );
      expect(invalidQueue.isFullyCompleted, isFalse);
    });

    test('aggregateRatio calculates byte-weighted when determinate, count-based when indeterminate', () {
      final determinateQueue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        completedItems: 10,
        totalExpectedBytes: 1000000,
        downloadedBytes: 250000,
        createdAt: now,
        updatedAt: now,
      );
      expect(determinateQueue.aggregateRatio, equals(0.25));

      final indeterminateQueue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        completedItems: 57,
        totalExpectedBytes: null,
        downloadedBytes: 500000,
        createdAt: now,
        updatedAt: now,
      );
      expect(indeterminateQueue.aggregateRatio, closeTo(57 / 114, 0.001));
    });

    test('activeItem, nextPendingItem, and failedItems helpers', () {
      final items = create114Items('q1');
      // Set item 0 (Surah 1) to completed, item 1 (Surah 2) to running, item 2 (Surah 3) to failed
      items[0] = items[0].copyWith(status: QuranDownloadQueueItemStatus.completed);
      items[1] = items[1].copyWith(status: QuranDownloadQueueItemStatus.running);
      items[2] = items[2].copyWith(status: QuranDownloadQueueItemStatus.failed);

      final queue = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        completedItems: 1,
        createdAt: now,
        updatedAt: now,
        items: items,
      );

      expect(queue.activeItem?.surahNumber, equals(2));
      expect(queue.nextPendingItem?.surahNumber, equals(4)); // item index 3 is next pending
      expect(queue.failedItems.length, equals(1));
      expect(queue.failedItems.first.surahNumber, equals(3));
      expect(queue.completedOrSkippedItems.length, equals(1));
    });
  });

  group('QA.6 Phase 6.2 - QuranDownloadQueueProgress Domain Tests', () {
    test('initial factory and percentage calculations', () {
      final progress = QuranDownloadQueueProgress.initial(
        queueId: 'q1',
        reciterId: '7',
        totalExpectedBytes: 1000000,
      );

      expect(progress.status, equals(QuranDownloadQueueStatus.pending));
      expect(progress.aggregateRatio, equals(0.0));
      expect(progress.aggregatePercentage, equals(0));
      expect(progress.totalItems, equals(114));
      expect(progress.completedItems, equals(0));

      final running = progress.copyWith(
        status: QuranDownloadQueueStatus.running,
        completedItems: 57,
        aggregateRatio: 0.504,
        activeSurahNumber: 58,
        activeSurahPosition: 57,
        activeItemProgress: DownloadProgress(
          surahNumber: 58,
          reciterId: '7',
          status: AudioDownloadStatus.downloading,
          downloadedBytes: 1024,
        ),
      );

      expect(running.isRunning, isTrue);
      expect(running.aggregatePercentage, equals(50));
      expect(running.activeSurahNumber, equals(58));
      expect(running.activeItemProgress?.downloadedBytes, equals(1024));
    });
  });

  group('QA.6 Phase 6.2 - DownloadReservationTicket & Coordinator Domain Tests', () {
    test('DownloadReservationTicket disposes idempotently and invokes callback once', () {
      int disposeCount = 0;
      final ticket = DownloadReservationTicket(
        description: 'Single-Surah(1, 7)',
        onDispose: () {
          disposeCount++;
        },
      );

      expect(ticket.isDisposed, isFalse);
      expect(ticket.description, equals('Single-Surah(1, 7)'));

      ticket.dispose();
      expect(ticket.isDisposed, isTrue);
      expect(disposeCount, equals(1));

      // Second dispose should be a no-op
      ticket.dispose();
      expect(disposeCount, equals(1));
    });

    test('QuranAudioConflictFailure has descriptive message', () {
      final defaultFailure = QuranAudioConflictFailure();
      expect(defaultFailure.message, contains('تعارض في عملية التنزيل'));

      final customFailure = QuranAudioConflictFailure(message: 'Custom conflict');
      expect(customFailure.message, equals('Custom conflict'));
    });
  });
}
