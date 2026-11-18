import 'package:dartz/dartz.dart';
import '../entities/audio_download.dart';
import '../entities/storage_reconciliation_summary.dart';
import '../errors/quran_audio_failures.dart';

/// Contract for managing downloaded Quran audio files, status verification,
/// registry persistence, and offline file deletion.
abstract class BaseAudioDownloadRepository {
  /// Checks whether a valid, verified downloaded file exists for [surahNumber] and [reciterId].
  Future<bool> isSurahDownloaded({
    required int surahNumber,
    required String reciterId,
  });

  /// Retrieves all completed download records for a specific reciter.
  Future<List<AudioDownload>> getDownloadedSurahs({
    required String reciterId,
  });

  /// Retrieves all completed download records across all reciters.
  Future<List<AudioDownload>> getAllDownloadedRecords();

  /// Persists a new or updated download record in local storage.
  Future<Either<QuranAudioFailure, void>> saveDownloadRecord(
    AudioDownload download,
  );

  /// Deletes a single downloaded Surah file and removes its record.
  Future<Either<QuranAudioFailure, void>> deleteDownloadRecord({
    required int surahNumber,
    required String reciterId,
  });

  /// Deletes all downloaded Surah files for a specific reciter.
  Future<Either<QuranAudioFailure, void>> deleteReciterDownloads({
    required String reciterId,
  });

  /// Deletes all downloaded Quran audio files across all reciters.
  Future<Either<QuranAudioFailure, void>> deleteAllDownloads();

  /// Resolves the absolute local filesystem path for a downloaded Surah,
  /// or null if the file does not exist locally.
  Future<String?> getLocalAudioPath({
    required int surahNumber,
    required String reciterId,
  });

  /// Scans physical storage and reconciles disk state with the database registry.
  Future<Either<QuranAudioFailure, StorageReconciliationSummary>> reconcileStorage();
}
