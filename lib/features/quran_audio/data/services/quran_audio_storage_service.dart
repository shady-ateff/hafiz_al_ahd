import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/promotion_journal_entry.dart';
import '../../domain/entities/storage_reconciliation_summary.dart';
import '../datasources/quran_audio_local_data_source.dart';
import '../models/audio_download_model.dart';
import '../models/promotion_journal_model.dart';

/// Service managing physical filesystem layout, symlink-aware security containment,
/// persistent promotion journal, crash-recovery reconciliation, and TOCTOU-safe cleanups.
class QuranAudioStorageService {
  static const String kQuranAudioDirName = 'quran_audio';
  static const String kStagingDirName = '.staging';
  static const String kQuarantineDirName = '.quarantine';

  /// 25 MB OS/WAL Safety Floor (Blueprint C6).
  static const int kSafetyFloorBytes = 25 * 1024 * 1024;

  final Directory Function()? customBaseDirectoryProvider;
  final Future<int?> Function()? customDiskSpaceProvider;

  const QuranAudioStorageService({
    this.customBaseDirectoryProvider,
    this.customDiskSpaceProvider,
  });

  /// Returns the available free disk space in bytes for the storage partition.
  ///
  /// Priority:
  /// 1. Uses [customDiskSpaceProvider] if injected (e.g. tests or platform bridges).
  /// 2. If running on Android/Linux, queries storage mount via `df -k`.
  /// 3. Returns null if platform disk space query is unsupported or fails,
  ///    allowing indeterminate preflight handling without blocking operations.
  Future<int?> getAvailableDiskSpace() async {
    if (customDiskSpaceProvider != null) {
      return await customDiskSpaceProvider!();
    }
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final storageDir = await getStorageDirectory();
        final result = await Process.run('df', ['-k', storageDir.path]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            final parts = lines[1].trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final availKb = int.tryParse(parts[3]);
              if (availKb != null) {
                return availKb * 1024;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[QuranAudioStorageService] getAvailableDiskSpace error: $e');
    }
    return null;
  }

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

  /// Resolves the quarantine directory used for isolated corrupt destination files.
  Future<Directory> getQuarantineDirectory() async {
    final storageDir = await getStorageDirectory();
    final quarantineDir = Directory(p.join(storageDir.path, kQuarantineDirName));
    if (!await quarantineDir.exists()) {
      await quarantineDir.create(recursive: true);
    }
    return quarantineDir;
  }

  /// Derives the standard relative path for a completed Surah file:
  /// `reciter_{reciterId}/surah_{001..114}.mp3`
  static String buildRelativePath(int surahNumber, String reciterId) {
    final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    return p.join('reciter_$cleanReciter', 'surah_$paddedSurah.mp3').replaceAll('\\', '/');
  }

  /// Calculates the full-file SHA-256 hex digest by streaming the file from byte 0 to EOF.
  Future<String> calculateSha256(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Cannot compute SHA-256 for non-existent file: ${file.path}');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
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

  /// Atomically promotes a staging file with full persistent journal tracking
  /// and zero data loss rollback guarantee (Rev 7 Contract D3-8 & Cond 2).
  Future<File> promoteStagingFileWithJournal({
    required File stagingFile,
    required int surahNumber,
    required String reciterId,
    required BaseQuranAudioLocalDataSource localDataSource,
    int? expectedSizeBytes,
    String? etag,
    String? lastModified,
  }) async {
    final storageDir = await getStorageDirectory();
    final quarantineDir = await getQuarantineDirectory();
    await _verifyPhysicalContainment(stagingFile, storageDir);

    final destinationFile = await resolveSurahFile(surahNumber, reciterId);
    final destDir = destinationFile.parent;
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // Step 1: Pre-calculate Staging SHA-256
    final stagingSha256 = await calculateSha256(stagingFile);
    final stagingLength = await stagingFile.length();

    File? backupFile;
    String? previousSha256;
    File? quarantineFile;
    String? quarantineSha256;
    PromotionJournalState initialState = PromotionJournalState.idle;

    // Step 2: Handle existing destination file if present
    if (await destinationFile.exists()) {
      final destLength = await destinationFile.length();
      final destSha256 = await calculateSha256(destinationFile);

      // If destination already exists and matches expected size & staging hash, it is already valid
      if (destLength > 0 &&
          (expectedSizeBytes == null || destLength == expectedSizeBytes) &&
          destSha256 == stagingSha256) {
        try {
          await stagingFile.delete();
        } catch (_) {}
        return destinationFile;
      }

      if (destLength > 0 && (expectedSizeBytes == null || destLength == expectedSizeBytes)) {
        // Valid destination being replaced -> Move to backup
        backupFile = File('${destinationFile.path}.bak');
        await destinationFile.rename(backupFile.path);
        previousSha256 = destSha256;
        initialState = PromotionJournalState.backupCreated;
      } else {
        // Corrupt or truncated destination -> Move to quarantine
        final paddedSurah = surahNumber.toString().padLeft(3, '0');
        quarantineFile = File(p.join(quarantineDir.path, 'corrupt_${reciterId}_$paddedSurah.tmp'));
        await destinationFile.rename(quarantineFile.path);
        quarantineSha256 = destSha256;
        initialState = PromotionJournalState.quarantined;
      }
    }

    // Step 3: Record promotion in persistent journal table
    final journalEntry = PromotionJournalModel(
      surahNumber: surahNumber,
      reciterId: reciterId,
      stagingPath: stagingFile.path,
      stagingSha256: stagingSha256,
      destinationPath: destinationFile.path,
      backupPath: backupFile?.path,
      previousSha256: previousSha256,
      quarantinePath: quarantineFile?.path,
      quarantineSha256: quarantineSha256,
      promotionState: initialState,
    );
    await localDataSource.savePromotionJournal(journalEntry);

    // Step 4: Atomic filesystem rename (staging -> destination)
    try {
      await stagingFile.rename(destinationFile.path);
    } catch (e) {
      debugPrint('[QuranAudioStorageService] Rename failed, trying copy: $e');
      await stagingFile.copy(destinationFile.path);
      await stagingFile.delete();
    }

    // Step 5: Update journal to staged_promoted
    await localDataSource.updatePromotionJournalState(
      surahNumber: surahNumber,
      reciterId: reciterId,
      state: PromotionJournalState.stagedPromoted,
    );

    // Step 6: Finalize in SQLite via atomic transaction
    final now = DateTime.now();
    final downloadModel = AudioDownloadModel(
      surahNumber: surahNumber,
      reciterId: reciterId,
      localRelativePath: buildRelativePath(surahNumber, reciterId),
      status: AudioDownloadStatus.completed,
      actualSizeBytes: stagingLength,
      expectedSizeBytes: expectedSizeBytes ?? stagingLength,
      sha256: stagingSha256,
      transferIntegrityVerified: true,
      etag: etag,
      lastModified: lastModified,
      downloadedAt: now,
      completedAt: now,
    );
    await localDataSource.finalizePromotion(
      download: downloadModel,
      surahNumber: surahNumber,
      reciterId: reciterId,
    );

    // Step 7: TOCTOU-safe cleanup of backup or quarantine file
    if (backupFile != null && await backupFile.exists()) {
      await cleanupBackupSafely(
        destinationFile: destinationFile,
        backupFile: backupFile,
        surahNumber: surahNumber,
        reciterId: reciterId,
        localDataSource: localDataSource,
      );
    }
    if (quarantineFile != null && await quarantineFile.exists()) {
      try {
        await quarantineFile.delete();
      } catch (_) {}
    }

    return destinationFile;
  }

  /// Backwards-compatible promotion method with optional journal support.
  Future<File> promoteStagingFile({
    required File stagingFile,
    required int surahNumber,
    required String reciterId,
    int? expectedSizeBytes,
    BaseQuranAudioLocalDataSource? localDataSource,
  }) async {
    if (localDataSource != null) {
      return promoteStagingFileWithJournal(
        stagingFile: stagingFile,
        surahNumber: surahNumber,
        reciterId: reciterId,
        localDataSource: localDataSource,
        expectedSizeBytes: expectedSizeBytes,
      );
    }

    final storageDir = await getStorageDirectory();
    await _verifyPhysicalContainment(stagingFile, storageDir);

    final destinationFile = await resolveSurahFile(surahNumber, reciterId);
    final destDir = destinationFile.parent;
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    if (await destinationFile.exists()) {
      final destLength = await destinationFile.length();
      if (destLength > 0 && (expectedSizeBytes == null || destLength == expectedSizeBytes)) {
        try {
          await stagingFile.delete();
        } catch (_) {}
        return destinationFile;
      }
      await destinationFile.delete();
    }

    try {
      return await stagingFile.rename(destinationFile.path);
    } catch (e) {
      debugPrint('[QuranAudioStorageService] Rename failed, attempting copy fallback: $e');
      final copied = await stagingFile.copy(destinationFile.path);
      await stagingFile.delete();
      return copied;
    }
  }

  /// TOCTOU-Safe Backup Cleanup Protocol (Rev 7 Implementation Condition 2).
  ///
  /// Executes the 7-assertion verification sequence before deleting an orphan backup file.
  Future<bool> cleanupBackupSafely({
    required File destinationFile,
    required File backupFile,
    required int surahNumber,
    required String reciterId,
    required BaseQuranAudioLocalDataSource localDataSource,
  }) async {
    try {
      final storageDir = await getStorageDirectory();

      // 1. Canonicalize destinationPath & backupPath
      // 2. Verify BOTH paths reside strictly within quran_audio/ root (no symlinks)
      await _verifyPhysicalContainment(destinationFile, storageDir);
      await _verifyPhysicalContainment(backupFile, storageDir);

      // 3. Check SQLite quran_audio_promotion_journal: ASSERT journal entry is NULL
      final journalEntry = await localDataSource.getPromotionJournal(surahNumber, reciterId);
      if (journalEntry != null) {
        debugPrint('[TOCTOU-Safe Cleanup] Aborted: Pending journal entry exists');
        return false;
      }

      // 4. Check SQLite quran_audio_downloads: ASSERT status == 'completed' AND sha256 IS NOT NULL
      final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
      if (record == null || record.status != AudioDownloadStatus.completed || record.sha256 == null) {
        debugPrint('[TOCTOU-Safe Cleanup] Aborted: Record is not completed or missing SHA-256');
        return false;
      }

      // 5. Open destinationFile for reading: ASSERT length > 0 AND length == actualSizeBytes
      if (!await destinationFile.exists()) {
        debugPrint('[TOCTOU-Safe Cleanup] Aborted: Destination file does not exist');
        return false;
      }
      final destLength = await destinationFile.length();
      if (destLength <= 0 || destLength != record.actualSizeBytes) {
        debugPrint('[TOCTOU-Safe Cleanup] Aborted: Destination file length mismatch');
        return false;
      }

      // 6. Verify destination SHA-256 matches DB recorded hash
      final currentSha256 = await calculateSha256(destinationFile);
      if (currentSha256 != record.sha256) {
        debugPrint('[TOCTOU-Safe Cleanup] Aborted: Destination file SHA-256 mismatch');
        return false;
      }

      // 7. Execute backupFile.delete()
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      return true;
    } catch (e) {
      debugPrint('[TOCTOU-Safe Cleanup] Error during backup cleanup: $e');
      return false;
    }
  }

  /// Crash Recovery Engine: Reconciles all interrupted transactions from the promotion journal
  /// adhering strictly to the Quarantine Crash Recovery Matrix (Rev 7 §2.3).
  Future<int> recoverPendingPromotionJournals(BaseQuranAudioLocalDataSource localDataSource) async {
    final pendingJournals = await localDataSource.getAllPromotionJournals();
    if (pendingJournals.isEmpty) return 0;

    int recoveredCount = 0;

    for (final entry in pendingJournals) {
      final destFile = File(entry.destinationPath);
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final stagingFile = File(entry.stagingPath);
      final backupFile = entry.backupPath != null ? File(entry.backupPath!) : null;
      final quarantineFile = entry.quarantinePath != null ? File(entry.quarantinePath!) : null;

      final destExists = await destFile.exists();
      final stagingExists = await stagingFile.exists();
      final backupExists = backupFile != null && await backupFile.exists();
      final quarantineExists = quarantineFile != null && await quarantineFile.exists();

      // Case 1: Quarantine in-flight crash (Dest Absent, Staging Present, Quarantine Present, state: quarantined)
      if (!destExists && stagingExists && quarantineExists && entry.promotionState == PromotionJournalState.quarantined) {
        final stagingSha256 = await calculateSha256(stagingFile);
        if (stagingSha256 == entry.stagingSha256) {
          await stagingFile.rename(destFile.path);
          await _finalizeRecovery(localDataSource, entry, destFile, stagingSha256);
          await quarantineFile.delete();
        } else {
          // Staging corrupted: Zero data loss rollback to quarantine
          await quarantineFile.rename(destFile.path);
          await localDataSource.removePromotionJournal(entry.surahNumber, entry.reciterId);
        }
        recoveredCount++;
        continue;
      }

      // Case 2: Crash after staging rename, before quarantine cleanup (Dest Present, Quarantine Present, state: staged_promoted)
      if (destExists && quarantineExists && entry.promotionState == PromotionJournalState.stagedPromoted) {
        final destSha256 = await calculateSha256(destFile);
        if (destSha256 == entry.stagingSha256) {
          await quarantineFile.delete();
          await _finalizeRecovery(localDataSource, entry, destFile, destSha256);
        }
        recoveredCount++;
        continue;
      }

      // Case 3: Staging lost during quarantine window (Dest Absent, Staging Absent, Quarantine Present)
      if (!destExists && !stagingExists && quarantineExists) {
        await quarantineFile.rename(destFile.path);
        await localDataSource.removePromotionJournal(entry.surahNumber, entry.reciterId);
        recoveredCount++;
        continue;
      }

      // Case 4: Backup crash recovery (Dest Absent, Staging Present, Backup Present, state: backup_created)
      if (!destExists && stagingExists && backupExists && entry.promotionState == PromotionJournalState.backupCreated) {
        final stagingSha256 = await calculateSha256(stagingFile);
        if (stagingSha256 == entry.stagingSha256) {
          await stagingFile.rename(destFile.path);
          await _finalizeRecovery(localDataSource, entry, destFile, stagingSha256);
          await cleanupBackupSafely(
            destinationFile: destFile,
            backupFile: backupFile,
            surahNumber: entry.surahNumber,
            reciterId: entry.reciterId,
            localDataSource: localDataSource,
          );
        } else {
          // Staging corrupt: Rollback backup to destination
          await backupFile.rename(destFile.path);
          await localDataSource.removePromotionJournal(entry.surahNumber, entry.reciterId);
        }
        recoveredCount++;
        continue;
      }

      // Case 5: Crash after staging rename, before backup cleanup (Dest Present, Backup Present, state: staged_promoted)
      if (destExists && backupExists && entry.promotionState == PromotionJournalState.stagedPromoted) {
        final destSha256 = await calculateSha256(destFile);
        if (destSha256 == entry.stagingSha256) {
          await _finalizeRecovery(localDataSource, entry, destFile, destSha256);
          await cleanupBackupSafely(
            destinationFile: destFile,
            backupFile: backupFile,
            surahNumber: entry.surahNumber,
            reciterId: entry.reciterId,
            localDataSource: localDataSource,
          );
        }
        recoveredCount++;
        continue;
      }

      // Fallback clean: if destination exists and matches staging SHA-256
      if (destExists) {
        final destSha256 = await calculateSha256(destFile);
        if (destSha256 == entry.stagingSha256) {
          await _finalizeRecovery(localDataSource, entry, destFile, destSha256);
          if (backupExists) await backupFile.delete();
          if (quarantineExists) await quarantineFile.delete();
          recoveredCount++;
          continue;
        }
      }

      // If cannot safely resolve, remove orphan journal entry to prevent deadlocks
      await localDataSource.removePromotionJournal(entry.surahNumber, entry.reciterId);
    }

    return recoveredCount;
  }

  Future<void> _finalizeRecovery(
    BaseQuranAudioLocalDataSource localDataSource,
    PromotionJournalEntry entry,
    File destFile,
    String sha256Hex,
  ) async {
    final now = DateTime.now();
    final length = await destFile.length();
    final downloadModel = AudioDownloadModel(
      surahNumber: entry.surahNumber,
      reciterId: entry.reciterId,
      localRelativePath: buildRelativePath(entry.surahNumber, entry.reciterId),
      status: AudioDownloadStatus.completed,
      actualSizeBytes: length,
      expectedSizeBytes: length,
      sha256: sha256Hex,
      transferIntegrityVerified: true,
      downloadedAt: entry.createdAt,
      completedAt: now,
    );
    await localDataSource.finalizePromotion(
      download: downloadModel,
      surahNumber: entry.surahNumber,
      reciterId: entry.reciterId,
    );
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
      if (parentName.startsWith('reciter_') &&
          fileName.startsWith('surah_') &&
          fileName.endsWith('.mp3')) {
        final reciterId = parentName.replaceFirst('reciter_', '');
        final surahPart = fileName.replaceFirst('surah_', '').replaceFirst('.mp3', '');
        final surahNumber = int.tryParse(surahPart);

        if (surahNumber != null && surahNumber >= 1 && surahNumber <= 114) {
          final fileSize = entity.lengthSync();
          if (fileSize > 0) {
            final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
            if (record == null || !record.isPlayable) {
              final relPath = buildRelativePath(surahNumber, reciterId);
              await localDataSource.saveDownloadRecord(AudioDownloadModel(
                surahNumber: surahNumber,
                reciterId: reciterId,
                localRelativePath: relPath,
                status: AudioDownloadStatus.completed,
                actualSizeBytes: fileSize,
                downloadedAt: entity.statSync().modified,
                completedAt: entity.statSync().modified,
                transferIntegrityVerified: false, // Discovered legacy asset
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
            await localDataSource.saveDownloadRecord(AudioDownloadModel(
              surahNumber: record.surahNumber,
              reciterId: record.reciterId,
              localRelativePath: record.localRelativePath,
              status: AudioDownloadStatus.missing,
              actualSizeBytes: 0,
              downloadedAt: record.downloadedAt,
              completedAt: null,
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
        ? Directory(p.join(
            storageDir.path, 'reciter_${reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}'))
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
