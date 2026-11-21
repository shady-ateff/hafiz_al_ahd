import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../../domain/entities/quran_download_queue.dart';
import '../../domain/entities/quran_download_queue_item.dart';
import '../../domain/entities/quran_download_queue_status.dart';
import '../../domain/errors/quran_audio_failures.dart';
import '../../domain/repositories/base_audio_download_queue_repository.dart';
import '../datasources/quran_audio_database.dart';
import '../models/quran_download_queue_item_model.dart';
import '../models/quran_download_queue_model.dart';

/// Concrete implementation of [BaseAudioDownloadQueueRepository] backed by [BaseQuranAudioDatabase].
class AudioDownloadQueueRepositoryImpl implements BaseAudioDownloadQueueRepository {
  final BaseQuranAudioDatabase database;

  AudioDownloadQueueRepositoryImpl({required this.database});

  @override
  Future<Either<Failure, QuranDownloadQueue?>> getActiveQueue() async {
    try {
      final model = await database.getActiveQueue();
      return Right(model?.toEntity());
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to retrieve active full-Quran download queue: $e',
      ));
    }
  }

  @override
  Future<Either<Failure, QuranDownloadQueue?>> getQueueById(String queueId) async {
    try {
      final model = await database.getQueueById(queueId);
      return Right(model?.toEntity());
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to retrieve full-Quran download queue by ID ($queueId): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, QuranDownloadQueue?>> getLatestQueueForReciter(
    String reciterId,
  ) async {
    try {
      final model = await database.getLatestQueueForReciter(reciterId);
      return Right(model?.toEntity());
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to retrieve latest queue for reciter ($reciterId): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> createQueue(QuranDownloadQueue queue) async {
    try {
      final queueModel = QuranDownloadQueueModel.fromEntity(queue);
      final itemModels = queue.items
          .map((i) => QuranDownloadQueueItemModel.fromEntity(i))
          .toList();

      await database.createQueue(
        queue: queueModel,
        items: itemModels,
      );
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to create and persist full-Quran download queue (${queue.id}): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> updateQueueStatus({
    required String queueId,
    required QuranDownloadQueueStatus status,
    DateTime? completedAt,
  }) async {
    try {
      await database.updateQueueStatus(
        queueId: queueId,
        status: status,
        completedAt: completedAt,
      );
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to update queue status ($queueId -> $status): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> updateQueueProgress({
    required String queueId,
    required int completedItems,
    required int downloadedBytes,
    int? totalExpectedBytes,
  }) async {
    try {
      await database.updateQueueProgress(
        queueId: queueId,
        completedItems: completedItems,
        downloadedBytes: downloadedBytes,
        totalExpectedBytes: totalExpectedBytes,
      );
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to update queue progress ($queueId): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> updateQueueItemStatus({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueItemStatus status,
    int? downloadedBytes,
    String? lastError,
  }) async {
    try {
      await database.updateQueueItemStatus(
        queueId: queueId,
        surahNumber: surahNumber,
        status: status,
        downloadedBytes: downloadedBytes,
        lastError: lastError,
      );
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to update queue item ($queueId, Surah $surahNumber -> $status): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> updateQueueAndItemStatusAtomic({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueStatus queueStatus,
    required QuranDownloadQueueItemStatus itemStatus,
    int? downloadedBytes,
    String? lastError,
  }) async {
    try {
      await database.updateQueueAndItemStatusAtomic(
        queueId: queueId,
        surahNumber: surahNumber,
        queueStatus: queueStatus,
        itemStatus: itemStatus,
        downloadedBytes: downloadedBytes,
        lastError: lastError,
      );
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed atomic update for queue and item ($queueId, Surah $surahNumber): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, List<QuranDownloadQueueItem>>> getQueueItems(
    String queueId,
  ) async {
    try {
      final models = await database.getQueueItems(queueId);
      return Right(models.map((m) => m.toEntity()).toList());
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to retrieve queue items ($queueId): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> retryFailedItems(String queueId) async {
    try {
      await database.retryFailedQueueItems(queueId);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to retry failed queue items ($queueId): $e',
      ));
    }
  }

  @override
  Future<Either<Failure, void>> deleteQueue(String queueId) async {
    try {
      await database.deleteQueue(queueId);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(
        message: 'Failed to delete full-Quran download queue ($queueId): $e',
      ));
    }
  }
}
