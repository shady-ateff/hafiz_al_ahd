import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/storage_reconciliation_summary.dart';
import '../datasources/quran_audio_local_data_source.dart';
import '../models/audio_download_model.dart';

/// Service managing the physical filesystem layout, symlink-aware security boundaries,
/// atomic promotions, and crash-recovery reconciliation for the Quran Audio subsystem.
class QuranAudioStorageService {
  static const String kQuranAudioDirName = 'quran_audio';
  static const String kStagingDirName = '.staging';

  final Directory Function()? customBaseDirectoryProvider;

  const QuranAudioStorageService({this.customBaseDirectoryProvider});

  /// Resolves the root Quran Audio storage directory.
  Future<Directory> getStorageDirectory() async {
    final baseDir = customBaseDirectoryProvider != null
        ? customBaseDirectoryProvider!()
        : await getApplicationDocumentsDirectory();

    final dir = Directory(p.join(baseDir.path, kQuranAudioDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolves the staging directory used for in-flight temporary downloads.
  Future<Directory> getStagingDirectory() async {
    final storageDir = await getStorageDirectory();
    final stagingDir = Directory(p.join(storageDir.path, kStagingDirName));
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }
    return stagingDir;
  }

  /// Derives the standard relative path for a completed Surah file:
  /// `reciter_{reciterId}/surah_{001..114}.mp3`
  static String buildRelativePath(int surahNumber, String reciterId) {
    final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    return p.join('reciter_$cleanReciter', 'surah_$paddedSurah.mp3').replaceAll('\\', '/');
  }

  /// Validates that [file] and its parent directory resolve strictly within [storageDir],
  /// resolving all symbolic links to prevent symlink escape vulnerabilities.
  Future<void> _verifyPhysicalContainment(File file, Directory storageDir) async {
    final canonicalRoot = p.canonicalize(storageDir.path);
    final canonicalTarget = p.canonicalize(file.path);

    // 1. Lexical containment check
    if (!p.isWithin(canonicalRoot, canonicalTarget)) {
      throw SecurityException('Lexical path traversal attempt blocked: ${file.path}');
    }

    // 2. Real symbolic link containment check
    try {
      final resolvedRoot = p.canonicalize(await storageDir.resolveSymbolicLinks());

      if (await file.exists()) {
        final resolvedFile = p.canonicalize(await file.resolveSymbolicLinks());
        if (!p.isWithin(resolvedRoot, resolvedFile)) {
          throw SecurityException('Symlink escape attempt blocked: ${file.path} -> $resolvedFile');
        }
      } else if (await file.parent.exists()) {
        final resolvedParent = p.canonicalize(await file.parent.resolveSymbolicLinks());
        if (resolvedParent != resolvedRoot && !p.isWithin(resolvedRoot, resolvedParent)) {
          throw SecurityException('Parent symlink escape attempt blocked: ${file.parent.path}');
        }
      }
    } on FileSystemException {
      // In constrained environments where resolveSymbolicLinks throws on non-existent targets
      if (!p.isWithin(canonicalRoot, canonicalTarget)) {
        throw SecurityException('Path boundary violation: ${file.path}');
      }
    }
  }

  /// Resolves the absolute [File] for a downloaded Surah, verifying path containment and symlinks.
  Future<File> resolveSurahFile(int surahNumber, String reciterId) async {
    final storageDir = await getStorageDirectory();
    final relPath = buildRelativePath(surahNumber, reciterId);
    final file = File(p.normalize(p.join(storageDir.path, relPath)));

    await _verifyPhysicalContainment(file, storageDir);
    return file;
  }

  /// Creates a temporary staging file for an active download.
  Future<File> createStagingFile(String token, int surahNumber, String reciterId) async {
    final stagingDir = await getStagingDirectory();
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    final fileName = 'dl_${token}_${reciterId}_$paddedSurah.tmp';
    final file = File(p.join(stagingDir.path, fileName));

    await _verifyPhysicalContainment(file, await getStorageDirectory());
    return file;
  }

  /// Atomically promotes a completed staging file to its final Surah destination
  /// with explicit target state handling.
  Future<File> promoteStagingFile({
    required File stagingFile,
    required int surahNumber,
    required String reciterId,
    int? expectedSizeBytes,
  }) async {
    final storageDir = await getStorageDirectory();
    await _verifyPhysicalContainment(stagingFile, storageDir);

    final destinationFile = await resolveSurahFile(surahNumber, reciterId);
    final destDir = destinationFile.parent;
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 1. Target existence check
    if (await destinationFile.exists()) {
      final destLength = await destinationFile.length();

      // If target exists and is valid, keep target and discard redundant staging
      if (destLength > 0 && (expectedSizeBytes == null || destLength == expectedSizeBytes)) {
        try {
          await stagingFile.delete();
        } catch (_) {}
        return destinationFile;
      }

      // Target exists but is corrupt / mismatched -> safe replacement
      await destinationFile.delete();
    }

    // 2. Atomic filesystem rename
    try {
      return await stagingFile.rename(destinationFile.path);
    } catch (e) {
      debugPrint('[QuranAudioStorageService] Rename failed, attempting copy fallback: $e');
      final copied = await stagingFile.copy(destinationFile.path);
      await stagingFile.delete();
      return copied;
    }
  }

  /// Deletes a specific Surah file if it exists.
  Future<bool> deleteSurahFile(int surahNumber, String reciterId) async {
    final file = await resolveSurahFile(surahNumber, reciterId);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Deletes all downloaded Surah files for a specific reciter.
  Future<int> deleteReciterDirectory(String reciterId) async {
    final storageDir = await getStorageDirectory();
    final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final reciterDir = Directory(p.join(storageDir.path, 'reciter_$cleanReciter'));

    await _verifyPhysicalContainment(File(reciterDir.path), storageDir);

    if (await reciterDir.exists()) {
      final files = reciterDir.listSync(recursive: true).whereType<File>();
      final count = files.length;
      await reciterDir.delete(recursive: true);
      return count;
    }
    return 0;
  }

  /// Deletes all Quran audio files and cleans up staging directory.
  Future<void> deleteAllQuranAudio() async {
    final storageDir = await getStorageDirectory();
    if (await storageDir.exists()) {
      await storageDir.delete(recursive: true);
      await storageDir.create(recursive: true);
    }
  }

  /// Reconciles the physical filesystem with the local database registry.
  ///
  /// Recovers from crashes where a file was promoted on disk before the database
  /// update completed, flags missing files, and cleans abandoned temporary downloads.
  Future<StorageReconciliationSummary> reconcileStorageWithRegistry(
    BaseQuranAudioLocalDataSource localDataSource, {
    Duration abandonedStagingThreshold = const Duration(hours: 1),
  }) async {
    final storageDir = await getStorageDirectory();
    if (!await storageDir.exists()) {
      return const StorageReconciliationSummary(
        discoveredFiles: 0,
        missingFiles: 0,
        cleanedTempFiles: 0,
      );
    }

    int discoveredCount = 0;
    int missingCount = 0;
    int cleanedTempCount = 0;

    final now = DateTime.now();

    // 1. Scan physical files to discover promoted files missing in DB
    final entities = storageDir.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;

      final fileName = p.basename(entity.path);

      // Check for staging files (.staging/*.tmp)
      if (fileName.endsWith('.tmp')) {
        try {
          final stat = entity.statSync();
          if (now.difference(stat.modified) > abandonedStagingThreshold) {
            entity.deleteSync();
            cleanedTempCount++;
          }
        } catch (_) {}
        continue;
      }

      // Check for Surah files (reciter_<id>/surah_<001..114>.mp3)
      final parentName = p.basename(entity.parent.path);
      if (parentName.startsWith('reciter_') && fileName.startsWith('surah_') && fileName.endsWith('.mp3')) {
        final reciterId = parentName.replaceFirst('reciter_', '');
        final surahPart = fileName.replaceFirst('surah_', '').replaceFirst('.mp3', '');
        final surahNumber = int.tryParse(surahPart);

        if (surahNumber != null && surahNumber >= 1 && surahNumber <= 114) {
          final fileSize = entity.lengthSync();
          if (fileSize > 0) {
            final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
            if (record == null || !record.isPlayable) {
              // Reconcile into DB as completed
              final relPath = buildRelativePath(surahNumber, reciterId);
              await localDataSource.saveDownloadRecord(AudioDownloadModel(
                surahNumber: surahNumber,
                reciterId: reciterId,
                localRelativePath: relPath,
                status: AudioDownloadStatus.completed,
                actualSizeBytes: fileSize,
                downloadedAt: entity.statSync().modified,
              ));
              discoveredCount++;
            }
          }
        }
      }
    }

    // 2. Scan DB records to verify physical files still exist
    final records = await localDataSource.getDownloadRecords();
    for (final record in records) {
      if (record.isPlayable) {
        try {
          final file = await resolveSurahFile(record.surahNumber, record.reciterId);
          if (!await file.exists() || await file.length() == 0) {
            // Mark missing in DB
            await localDataSource.saveDownloadRecord(AudioDownloadModel(
              surahNumber: record.surahNumber,
              reciterId: record.reciterId,
              localRelativePath: record.localRelativePath,
              status: AudioDownloadStatus.missing,
              actualSizeBytes: 0,
              downloadedAt: record.downloadedAt,
            ));
            missingCount++;
          }
        } catch (_) {}
      }
    }

    return StorageReconciliationSummary(
      discoveredFiles: discoveredCount,
      missingFiles: missingCount,
      cleanedTempFiles: cleanedTempCount,
    );
  }

  /// Calculates total bytes used by completed Quran audio downloads.
  Future<int> calculateStorageUsageBytes({String? reciterId}) async {
    final storageDir = await getStorageDirectory();
    if (!await storageDir.exists()) return 0;

    final targetDir = reciterId != null
        ? Directory(p.join(storageDir.path, 'reciter_${reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}'))
        : storageDir;

    if (!await targetDir.exists()) return 0;

    int totalBytes = 0;
    final entities = targetDir.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is File && !p.basename(entity.path).endsWith('.tmp')) {
        try {
          totalBytes += entity.lengthSync();
        } catch (_) {}
      }
    }
    return totalBytes;
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
