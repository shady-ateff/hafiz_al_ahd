import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/quran_download_queue_item_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/quran_download_queue_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_queue_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_item.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BaseQuranAudioDatabase database;
  late AudioDownloadQueueRepositoryImpl repository;

  setUp(() async {
    database = QuranAudioDatabase.inMemory();
    await database.init();
    repository = AudioDownloadQueueRepositoryImpl(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  List<QuranDownloadQueueItem> create114Items(
    String queueId, {
    QuranDownloadQueueItemStatus defaultStatus = QuranDownloadQueueItemStatus.pending,
  }) {
    final now = DateTime.now();
    return List.generate(114, (index) {
      return QuranDownloadQueueItem(
        id: '${queueId}_${index + 1}',
        queueId: queueId,
        surahNumber: index + 1,
        position: index,
        status: defaultStatus,
        expectedBytes: 1048576,
        downloadedBytes: 0,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  group('QA.6 Phase 6.3 - Database Schema v3 & Models Test', () {
    test('database version is bumped to 3', () {
      expect(QuranAudioDatabase.kDatabaseVersion, equals(3));
    });

    test('QuranDownloadQueueItemModel toMap and fromMap serialization', () {
      final now = DateTime.now();
      final model = QuranDownloadQueueItemModel(
        id: 'q1_1',
        queueId: 'q1',
        surahNumber: 1,
        position: 0,
        status: QuranDownloadQueueItemStatus.running,
        expectedBytes: 524288,
        downloadedBytes: 262144,
        attemptCount: 1,
        lastError: null,
        createdAt: now,
        updatedAt: now,
      );

      final map = model.toMap();
      final fromMap = QuranDownloadQueueItemModel.fromMap(map);

      expect(fromMap.id, equals('q1_1'));
      expect(fromMap.queueId, equals('q1'));
      expect(fromMap.surahNumber, equals(1));
      expect(fromMap.position, equals(0));
      expect(fromMap.status, equals(QuranDownloadQueueItemStatus.running));
      expect(fromMap.expectedBytes, equals(524288));
      expect(fromMap.downloadedBytes, equals(262144));
      expect(fromMap.attemptCount, equals(1));
    });

    test('QuranDownloadQueueModel toMap and fromMap serialization', () {
      final now = DateTime.now();
      final model = QuranDownloadQueueModel(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: 10,
        totalExpectedBytes: 119537664,
        downloadedBytes: 10485760,
        createdAt: now,
        updatedAt: now,
        completedAt: null,
      );

      final map = model.toMap();
      final fromMap = QuranDownloadQueueModel.fromMap(map);

      expect(fromMap.id, equals('q1'));
      expect(fromMap.reciterId, equals('7'));
      expect(fromMap.status, equals(QuranDownloadQueueStatus.running));
      expect(fromMap.totalItems, equals(114));
      expect(fromMap.completedItems, equals(10));
      expect(fromMap.totalExpectedBytes, equals(119537664));
      expect(fromMap.downloadedBytes, equals(10485760));
    });
  });

  group('QA.6 Phase 6.3 - Repository CRUD & Single Active Queue Invariant', () {
    test('createQueue persists queue and 114 items ordered by position ASC', () async {
      final now = DateTime.now();
      final items = create114Items('queue_reciter_7');
      final queue = QuranDownloadQueue(
        id: 'queue_reciter_7',
        reciterId: '7',
        status: QuranDownloadQueueStatus.pending,
        createdAt: now,
        updatedAt: now,
        items: items,
      );

      final createResult = await repository.createQueue(queue);
      expect(createResult.isRight(), isTrue);

      final getResult = await repository.getQueueById('queue_reciter_7');
      expect(getResult.isRight(), isTrue);
      final retrieved = getResult.getOrElse(() => null);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('queue_reciter_7'));
      expect(retrieved.items.length, equals(114));

      // Assert strict position alignment items[i].position == i
      for (int i = 0; i < 114; i++) {
        expect(retrieved.items[i].position, equals(i));
        expect(retrieved.items[i].surahNumber, equals(i + 1));
      }
    });

    test('getActiveQueue returns queue when pending, running, or paused', () async {
      final now = DateTime.now();
      final queue = QuranDownloadQueue(
        id: 'q_active',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q_active'),
      );

      await repository.createQueue(queue);

      final active = await repository.getActiveQueue();
      expect(active.isRight(), isTrue);
      expect(active.getOrElse(() => null)?.id, equals('q_active'));

      // Transition to paused -> still active
      await repository.updateQueueStatus(
        queueId: 'q_active',
        status: QuranDownloadQueueStatus.paused,
      );

      final pausedActive = await repository.getActiveQueue();
      expect(pausedActive.getOrElse(() => null)?.status, equals(QuranDownloadQueueStatus.paused));

      // Transition to completed -> no longer active
      await repository.updateQueueStatus(
        queueId: 'q_active',
        status: QuranDownloadQueueStatus.completed,
      );

      final completedActive = await repository.getActiveQueue();
      expect(completedActive.getOrElse(() => null), isNull);
    });

    test('enforces single active queue invariant (cannot create second active queue)', () async {
      final now = DateTime.now();
      final q1 = QuranDownloadQueue(
        id: 'q1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q1'),
      );
      await repository.createQueue(q1);

      final q2 = QuranDownloadQueue(
        id: 'q2',
        reciterId: '8',
        status: QuranDownloadQueueStatus.pending,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q2'),
      );

      // Attempting to create second active queue must fail
      final result2 = await repository.createQueue(q2);
      expect(result2.isLeft(), isTrue);
    });

    test('deleteQueue removes queue and cascade-deletes items', () async {
      final now = DateTime.now();
      final queue = QuranDownloadQueue(
        id: 'q_del',
        reciterId: '7',
        status: QuranDownloadQueueStatus.pending,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q_del'),
      );
      await repository.createQueue(queue);

      final deleteResult = await repository.deleteQueue('q_del');
      expect(deleteResult.isRight(), isTrue);

      final getResult = await repository.getQueueById('q_del');
      expect(getResult.getOrElse(() => null), isNull);

      final itemsResult = await repository.getQueueItems('q_del');
      expect(itemsResult.getOrElse(() => []), isEmpty);
    });
  });

  group('QA.6 Phase 6.3 - Atomic State Mutations & Retry Logic', () {
    test('updateQueueAndItemStatusAtomic updates item and queue in single atomic unit', () async {
      final now = DateTime.now();
      final queue = QuranDownloadQueue(
        id: 'q_atomic',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q_atomic'),
      );
      await repository.createQueue(queue);

      final atomicResult = await repository.updateQueueAndItemStatusAtomic(
        queueId: 'q_atomic',
        surahNumber: 2,
        queueStatus: QuranDownloadQueueStatus.paused,
        itemStatus: QuranDownloadQueueItemStatus.paused,
        downloadedBytes: 524288,
      );
      expect(atomicResult.isRight(), isTrue);

      final updatedQueue = (await repository.getQueueById('q_atomic')).getOrElse(() => null);
      expect(updatedQueue!.status, equals(QuranDownloadQueueStatus.paused));

      final updatedItem = updatedQueue.items.firstWhere((i) => i.surahNumber == 2);
      expect(updatedItem.status, equals(QuranDownloadQueueItemStatus.paused));
      expect(updatedItem.downloadedBytes, equals(524288));
    });

    test('retryFailedItems resets failed items to pending and resumes queue to running', () async {
      final now = DateTime.now();
      final items = create114Items('q_retry');
      final queue = QuranDownloadQueue(
        id: 'q_retry',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        createdAt: now,
        updatedAt: now,
        items: items,
      );
      await repository.createQueue(queue);

      // Complete Surah 1, Fail Surah 2
      await repository.updateQueueItemStatus(
        queueId: 'q_retry',
        surahNumber: 1,
        status: QuranDownloadQueueItemStatus.completed,
      );
      await repository.updateQueueItemStatus(
        queueId: 'q_retry',
        surahNumber: 2,
        status: QuranDownloadQueueItemStatus.failed,
        lastError: 'ENOSPC: Insufficient disk space',
      );
      await repository.updateQueueStatus(
        queueId: 'q_retry',
        status: QuranDownloadQueueStatus.failed,
      );

      // Trigger Retry
      final retryResult = await repository.retryFailedItems('q_retry');
      expect(retryResult.isRight(), isTrue);

      final retriedQueue = (await repository.getQueueById('q_retry')).getOrElse(() => null);
      expect(retriedQueue!.status, equals(QuranDownloadQueueStatus.running));

      final item1 = retriedQueue.items.firstWhere((i) => i.surahNumber == 1);
      expect(item1.status, equals(QuranDownloadQueueItemStatus.completed),
          reason: 'Completed items must remain completed');

      final item2 = retriedQueue.items.firstWhere((i) => i.surahNumber == 2);
      expect(item2.status, equals(QuranDownloadQueueItemStatus.pending),
          reason: 'Failed item must be reset to pending');
      expect(item2.attemptCount, equals(1),
          reason: 'Attempt count must be incremented on retry');
      expect(item2.lastError, isNull,
          reason: 'Error message must be cleared on retry');
    });

    test('updateQueueProgress updates completedItems and downloadedBytes', () async {
      final now = DateTime.now();
      final queue = QuranDownloadQueue(
        id: 'q_progress',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        createdAt: now,
        updatedAt: now,
        items: create114Items('q_progress'),
      );
      await repository.createQueue(queue);

      final result = await repository.updateQueueProgress(
        queueId: 'q_progress',
        completedItems: 5,
        downloadedBytes: 5242880,
      );
      expect(result.isRight(), isTrue);

      final updated = (await repository.getQueueById('q_progress')).getOrElse(() => null);
      expect(updated!.completedItems, equals(5));
      expect(updated.downloadedBytes, equals(5242880));
    });
  });
}
