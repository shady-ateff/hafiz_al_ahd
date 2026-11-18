import 'package:dartz/dartz.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/storage_reconciliation_summary.dart';
import '../../domain/errors/quran_audio_failures.dart';
import '../../domain/repositories/base_audio_download_repository.dart';
import '../datasources/quran_audio_local_data_source.dart';
import '../models/audio_download_model.dart';
import '../services/quran_audio_storage_service.dart';

class AudioDownloadRepositoryImpl implements BaseAudioDownloadRepository {
  final BaseQuranAudioLocalDataSource localDataSource;
  final QuranAudioStorageService storageService;

  AudioDownloadRepositoryImpl({
    required this.localDataSource,
    required this.storageService,
  });

  @override
  Future<bool> isSurahDownloaded({
    required int surahNumber,
    required String reciterId,
  }) async {
    // 1. Check registry record
    final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
    if (record == null || !record.isPlayable) return false;

    // 2. Validate physical file existence on disk
    try {
      final file = await storageService.resolveSurahFile(surahNumber, reciterId);
      final exists = await file.exists();
      if (!exists) {
        // Self-healing: if file was removed externally, clean up stale registry record
        await localDataSource.removeDownloadRecord(surahNumber, reciterId);
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<AudioDownload>> getDownloadedSurahs({
    required String reciterId,
  }) async {
    final records = await localDataSource.getDownloadRecords(reciterId: reciterId);
    final validRecords = <AudioDownload>[];

    for (final record in records) {
      if (record.isPlayable) {
        try {
          final file = await storageService.resolveSurahFile(
            record.surahNumber,
            record.reciterId,
          );
          if (await file.exists()) {
            validRecords.add(record);
          } else {
            // Clean up stale record
            await localDataSource.removeDownloadRecord(record.surahNumber, record.reciterId);
          }
        } catch (_) {}
      }
    }

    return validRecords;
  }

  @override
  Future<List<AudioDownload>> getAllDownloadedRecords() async {
    final records = await localDataSource.getDownloadRecords();
    return records.where((r) => r.isPlayable).toList();
  }

  @override
  Future<Either<QuranAudioFailure, void>> saveDownloadRecord(
    AudioDownload download,
  ) async {
    try {
      final model = download is AudioDownloadModel
          ? download
          : AudioDownloadModel.fromEntity(download);
      await localDataSource.saveDownloadRecord(model);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حفظ سجل التنزيل: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, void>> deleteDownloadRecord({
    required int surahNumber,
    required String reciterId,
  }) async {
    try {
      // 1. Delete physical file
      await storageService.deleteSurahFile(surahNumber, reciterId);

      // 2. Remove registry record
      await localDataSource.removeDownloadRecord(surahNumber, reciterId);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حذف الملف الصوتي: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, void>> deleteReciterDownloads({
    required String reciterId,
  }) async {
    try {
      // 1. Delete physical reciter directory
      await storageService.deleteReciterDirectory(reciterId);

      // 2. Remove reciter registry records
      await localDataSource.removeReciterDownloadRecords(reciterId);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حذف تسجيلات القارئ: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, void>> deleteAllDownloads() async {
    try {
      await storageService.deleteAllQuranAudio();
      await localDataSource.clearAllDownloadRecords();
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حذف جميع التنزيلات: $e'));
    }
  }

  @override
  Future<String?> getLocalAudioPath({
    required int surahNumber,
    required String reciterId,
  }) async {
    final isDownloaded = await isSurahDownloaded(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );
    if (!isDownloaded) return null;

    final file = await storageService.resolveSurahFile(surahNumber, reciterId);
    return file.path;
  }

  @override
  Future<Either<QuranAudioFailure, StorageReconciliationSummary>> reconcileStorage() async {
    try {
      final summary = await storageService.reconcileStorageWithRegistry(localDataSource);
      return Right(summary);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل التوفيق بين التخزين المحلي وقاعدة البيانات: $e'));
    }
  }
}
