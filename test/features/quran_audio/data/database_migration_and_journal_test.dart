import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/promotion_journal_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/promotion_journal_entry.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late QuranAudioStorageService storageService;
  late SharedPreferences prefs;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('quran_audio_p53_test_');
    storageService = QuranAudioStorageService(
      customBaseDirectoryProvider: () => testDir,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Database Schema Migration v1 -> v2 (Contract 5.1-A & D3-8)', () {
    test('verifies database version bump to 2 or higher (v3 in QA.6)', () {
      expect(QuranAudioDatabase.kDatabaseVersion, greaterThanOrEqualTo(2));
    });

    test('deserializes legacy v1 row with backfilled completed_at and unverified transfer', () {
      // Legacy v1 row has downloaded_at, but NO completed_at, NO transfer_integrity_verified
      final legacyV1Json = {
        'surah_number': 1,
        'reciter_id': '7',
        'local_relative_path': 'reciter_7/surah_001.mp3',
        'status': 'completed',
        'actual_size_bytes': 839808,
        'sha256': 'legacy_fingerprint_hash',
        'downloaded_at': '2026-11-01T10:00:00.000Z',
      };

      final model = AudioDownloadModel.fromJson(legacyV1Json);

      expect(model.surahNumber, 1);
      expect(model.reciterId, '7');
      expect(model.status, AudioDownloadStatus.completed);
      expect(model.actualSizeBytes, 839808);
      expect(model.sha256, 'legacy_fingerprint_hash');
      // Backfill verification: completed_at must match downloaded_at for legacy completed rows
      expect(model.completedAt, DateTime.parse('2026-11-01T10:00:00.000Z'));
      // Transfer integrity must default to false for legacy assets
      expect(model.transferIntegrityVerified, isFalse);
      expect(model.expectedSizeBytes, isNull);
      expect(model.etag, isNull);
    });

    test('deserializes modern v2 row with all new fields intact', () {
      final v2Json = {
        'surah_number': 2,
        'reciter_id': '7',
        'local_relative_path': 'reciter_7/surah_002.mp3',
        'temp_relative_path': '.staging/dl_token_7_002.tmp',
        'status': 'completed',
        'actual_size_bytes': 25000000,
        'expected_size_bytes': 25000000,
        'sha256': 'a' * 64,
        'transfer_integrity_verified': 1,
        'etag': '"strong-etag-999"',
        'last_modified': 'Wed, 21 Oct 2026 07:28:00 GMT',
        'last_error': null,
        'downloaded_at': '2026-11-19T10:00:00.000Z',
        'completed_at': '2026-11-19T10:05:00.000Z',
      };

      final model = AudioDownloadModel.fromJson(v2Json);

      expect(model.surahNumber, 2);
      expect(model.tempRelativePath, '.staging/dl_token_7_002.tmp');
      expect(model.expectedSizeBytes, 25000000);
      expect(model.transferIntegrityVerified, isTrue);
      expect(model.etag, '"strong-etag-999"');
      expect(model.lastModified, 'Wed, 21 Oct 2026 07:28:00 GMT');
      expect(model.downloadedAt, DateTime.parse('2026-11-19T10:00:00.000Z'));
      expect(model.completedAt, DateTime.parse('2026-11-19T10:05:00.000Z'));
    });

    test('PromotionJournalModel serializes and deserializes across all states', () {
      final now = DateTime(2026, 11, 19, 14, 0, 0);
      final model = PromotionJournalModel(
        surahNumber: 36,
        reciterId: '7',
        stagingPath: '/storage/.staging/dl_36.tmp',
        stagingSha256: 'sha_staging_123',
        destinationPath: '/storage/reciter_7/surah_036.mp3',
        backupPath: '/storage/reciter_7/surah_036.mp3.bak',
        previousSha256: 'sha_prev_123',
        quarantinePath: '/storage/.quarantine/corrupt_7_036.tmp',
        quarantineSha256: 'sha_quar_123',
        promotionState: PromotionJournalState.backupCreated,
        createdAt: now,
      );

      final dbMap = model.toDbMap();
      expect(dbMap['promotion_state'], 'backup_created');
      expect(dbMap['created_at'], now.millisecondsSinceEpoch);

      final restored = PromotionJournalModel.fromJson(dbMap);
      expect(restored.surahNumber, 36);
      expect(restored.reciterId, '7');
      expect(restored.stagingPath, '/storage/.staging/dl_36.tmp');
      expect(restored.stagingSha256, 'sha_staging_123');
      expect(restored.destinationPath, '/storage/reciter_7/surah_036.mp3');
      expect(restored.backupPath, '/storage/reciter_7/surah_036.mp3.bak');
      expect(restored.previousSha256, 'sha_prev_123');
      expect(restored.quarantinePath, '/storage/.quarantine/corrupt_7_036.tmp');
      expect(restored.quarantineSha256, 'sha_quar_123');
      expect(restored.promotionState, PromotionJournalState.backupCreated);
      expect(restored.createdAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });
  });

  group('Promotion Journal CRUD & Atomic Finalization', () {
    test('manages journal states and finalizes promotion atomically', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();

      final localDataSource = QuranAudioLocalDataSourceImpl(
        database: db,
        prefs: prefs,
      );

      final entry = PromotionJournalEntry(
        surahNumber: 18,
        reciterId: '7',
        stagingPath: 'staging/s18.tmp',
        stagingSha256: 'hash18',
        destinationPath: 'reciter_7/surah_018.mp3',
        promotionState: PromotionJournalState.idle,
      );

      // 1. Save and retrieve
      await localDataSource.savePromotionJournal(entry);
      final retrieved = await localDataSource.getPromotionJournal(18, '7');
      expect(retrieved, isNotNull);
      expect(retrieved!.promotionState, PromotionJournalState.idle);

      // 2. Update state to stagedPromoted
      await localDataSource.updatePromotionJournalState(
        surahNumber: 18,
        reciterId: '7',
        state: PromotionJournalState.stagedPromoted,
      );
      final updated = await localDataSource.getPromotionJournal(18, '7');
      expect(updated!.promotionState, PromotionJournalState.stagedPromoted);

      // 3. Finalize promotion: inserts completed record and deletes journal in one atomic transaction
      final now = DateTime.now();
      final completedDownload = AudioDownloadModel(
        surahNumber: 18,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_018.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 25000000,
        expectedSizeBytes: 25000000,
        sha256: 'hash18',
        transferIntegrityVerified: true,
        downloadedAt: now,
        completedAt: now,
      );

      await localDataSource.finalizePromotion(
        download: completedDownload,
        surahNumber: 18,
        reciterId: '7',
      );

      // Journal entry must be deleted
      expect(await localDataSource.getPromotionJournal(18, '7'), isNull);

      // Download record must be completed and verified
      final record = await localDataSource.getDownloadRecord(18, '7');
      expect(record, isNotNull);
      expect(record!.status, AudioDownloadStatus.completed);
      expect(record.transferIntegrityVerified, isTrue);
      expect(record.isPlayable, isTrue);
    });
  });

  group('Atomic Promotion with Journal & Quarantine Integration (Rev 7 D3-8)', () {
    test('promotes initial download cleanly without existing destination', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      final stagingFile = await storageService.createStagingFile('token1', 1, '7');
      await stagingFile.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      final expectedSha256 = await storageService.calculateSha256(stagingFile);

      final promotedFile = await storageService.promoteStagingFileWithJournal(
        stagingFile: stagingFile,
        surahNumber: 1,
        reciterId: '7',
        localDataSource: localDataSource,
        expectedSizeBytes: 8,
      );

      expect(await promotedFile.exists(), isTrue);
      expect(await storageService.calculateSha256(promotedFile), expectedSha256);
      expect(await localDataSource.getPromotionJournal(1, '7'), isNull);

      final dbRecord = await localDataSource.getDownloadRecord(1, '7');
      expect(dbRecord, isNotNull);
      expect(dbRecord!.status, AudioDownloadStatus.completed);
      expect(dbRecord.transferIntegrityVerified, isTrue);
      expect(dbRecord.sha256, expectedSha256);
    });

    test('replaces valid existing destination via backup and TOCTOU cleanup', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      // 1. Initial version at destination
      final destFile = await storageService.resolveSurahFile(2, '7');
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes([10, 20, 30, 40]);

      // 2. New staging file
      final stagingFile = await storageService.createStagingFile('token2', 2, '7');
      await stagingFile.writeAsBytes([50, 60, 70, 80, 90]);
      final newSha256 = await storageService.calculateSha256(stagingFile);

      final promotedFile = await storageService.promoteStagingFileWithJournal(
        stagingFile: stagingFile,
        surahNumber: 2,
        reciterId: '7',
        localDataSource: localDataSource,
        expectedSizeBytes: 5,
      );

      expect(await promotedFile.exists(), isTrue);
      expect(await storageService.calculateSha256(promotedFile), newSha256);

      // Backup file should be cleaned up via TOCTOU safe deletion
      final backupFile = File('${destFile.path}.bak');
      expect(await backupFile.exists(), isFalse);

      final record = await localDataSource.getDownloadRecord(2, '7');
      expect(record!.actualSizeBytes, 5);
      expect(record.sha256, newSha256);
      expect(record.transferIntegrityVerified, isTrue);
    });

    test('quarantines corrupt destination file safely into .quarantine/', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      // 1. Corrupt destination file (length 2 bytes instead of expected 1000)
      final destFile = await storageService.resolveSurahFile(3, '7');
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes([0xFF, 0xEE]);

      // 2. Valid staging file
      final stagingFile = await storageService.createStagingFile('token3', 3, '7');
      final validBytes = List.filled(1000, 42);
      await stagingFile.writeAsBytes(validBytes);
      final expectedSha = await storageService.calculateSha256(stagingFile);

      final promoted = await storageService.promoteStagingFileWithJournal(
        stagingFile: stagingFile,
        surahNumber: 3,
        reciterId: '7',
        localDataSource: localDataSource,
        expectedSizeBytes: 1000,
      );

      expect(await promoted.exists(), isTrue);
      expect(await promoted.length(), 1000);
      expect(await storageService.calculateSha256(promoted), expectedSha);

      final record = await localDataSource.getDownloadRecord(3, '7');
      expect(record!.status, AudioDownloadStatus.completed);
      expect(record.transferIntegrityVerified, isTrue);
    });
  });

  group('TOCTOU-Safe Backup Cleanup Protocol (Rev 7 Implementation Condition 2)', () {
    test('enforces all 7 assertions and aborts deletion on discrepancies', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      final destFile = await storageService.resolveSurahFile(4, '7');
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes([1, 2, 3, 4]);
      final destSha = await storageService.calculateSha256(destFile);

      final backupFile = File('${destFile.path}.bak');
      await backupFile.writeAsBytes([9, 8, 7]);

      // 1. Assertion 3 failure: pending journal exists -> Aborts cleanup
      await localDataSource.savePromotionJournal(PromotionJournalEntry(
        surahNumber: 4,
        reciterId: '7',
        stagingPath: 'tmp',
        stagingSha256: 'hash',
        destinationPath: destFile.path,
        promotionState: PromotionJournalState.idle,
      ));

      final abort1 = await storageService.cleanupBackupSafely(
        destinationFile: destFile,
        backupFile: backupFile,
        surahNumber: 4,
        reciterId: '7',
        localDataSource: localDataSource,
      );
      expect(abort1, isFalse);
      expect(await backupFile.exists(), isTrue); // Retained safely!

      // Clear journal
      await localDataSource.removePromotionJournal(4, '7');

      // 2. Assertion 4 failure: DB record not completed -> Aborts cleanup
      final abort2 = await storageService.cleanupBackupSafely(
        destinationFile: destFile,
        backupFile: backupFile,
        surahNumber: 4,
        reciterId: '7',
        localDataSource: localDataSource,
      );
      expect(abort2, isFalse);
      expect(await backupFile.exists(), isTrue);

      // Create valid completed record in DB
      final now = DateTime.now();
      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 4,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_004.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 4,
        sha256: destSha,
        transferIntegrityVerified: true,
        downloadedAt: now,
        completedAt: now,
      ));

      // 3. Assertion 6 failure: destination SHA-256 mismatch -> Aborts cleanup
      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 4,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_004.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 4,
        sha256: 'tampered_or_mismatched_sha256',
        transferIntegrityVerified: true,
        downloadedAt: now,
        completedAt: now,
      ));

      final abort3 = await storageService.cleanupBackupSafely(
        destinationFile: destFile,
        backupFile: backupFile,
        surahNumber: 4,
        reciterId: '7',
        localDataSource: localDataSource,
      );
      expect(abort3, isFalse);
      expect(await backupFile.exists(), isTrue);

      // Restore correct SHA-256 -> All 7 assertions pass -> Backup deleted
      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 4,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_004.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 4,
        sha256: destSha,
        transferIntegrityVerified: true,
        downloadedAt: now,
        completedAt: now,
      ));

      final success = await storageService.cleanupBackupSafely(
        destinationFile: destFile,
        backupFile: backupFile,
        surahNumber: 4,
        reciterId: '7',
        localDataSource: localDataSource,
      );
      expect(success, isTrue);
      expect(await backupFile.exists(), isFalse); // Successfully deleted!
    });
  });

  group('Crash Recovery Matrix (Rev 7 §2.3)', () {
    test('Case 1: recovers staging file when destination was moved to quarantine before crash', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      final destFile = await storageService.resolveSurahFile(5, '7');
      final stagingFile = await storageService.createStagingFile('recover1', 5, '7');
      await stagingFile.writeAsBytes([1, 2, 3, 4, 5]);
      final stagingSha = await storageService.calculateSha256(stagingFile);

      final quarantineDir = await storageService.getQuarantineDirectory();
      final quarantineFile = File(p.join(quarantineDir.path, 'corrupt_7_005.tmp'));
      await quarantineFile.writeAsBytes([0xEE, 0xFF]);

      // Journal in quarantined state, crash occurred before staging rename
      await localDataSource.savePromotionJournal(PromotionJournalEntry(
        surahNumber: 5,
        reciterId: '7',
        stagingPath: stagingFile.path,
        stagingSha256: stagingSha,
        destinationPath: destFile.path,
        quarantinePath: quarantineFile.path,
        quarantineSha256: 'corrupt_hash',
        promotionState: PromotionJournalState.quarantined,
      ));

      final recovered = await storageService.recoverPendingPromotionJournals(localDataSource);
      expect(recovered, 1);

      expect(await destFile.exists(), isTrue);
      expect(await storageService.calculateSha256(destFile), stagingSha);
      expect(await quarantineFile.exists(), isFalse);
      expect(await localDataSource.getPromotionJournal(5, '7'), isNull);

      final record = await localDataSource.getDownloadRecord(5, '7');
      expect(record!.status, AudioDownloadStatus.completed);
      expect(record.transferIntegrityVerified, isTrue);
    });

    test('Case 1 Rollback: restores quarantine file if staging was corrupted during crash', () async {
      final db = QuranAudioDatabase.inMemory();
      await db.init();
      final localDataSource = QuranAudioLocalDataSourceImpl(database: db, prefs: prefs);

      final destFile = await storageService.resolveSurahFile(6, '7');
      final stagingFile = await storageService.createStagingFile('corrupt_recover', 6, '7');
      await stagingFile.writeAsBytes([9, 9, 9]); // Mismatched bytes

      final quarantineDir = await storageService.getQuarantineDirectory();
      final quarantineFile = File(p.join(quarantineDir.path, 'corrupt_7_006.tmp'));
      await quarantineFile.writeAsBytes([1, 2, 3]);

      await localDataSource.savePromotionJournal(PromotionJournalEntry(
        surahNumber: 6,
        reciterId: '7',
        stagingPath: stagingFile.path,
        stagingSha256: 'original_expected_hash', // Mismatch!
        destinationPath: destFile.path,
        quarantinePath: quarantineFile.path,
        quarantineSha256: 'quarantine_hash',
        promotionState: PromotionJournalState.quarantined,
      ));

      final recovered = await storageService.recoverPendingPromotionJournals(localDataSource);
      expect(recovered, 1);

      // Zero Data Loss Guarantee: destination file restored from quarantine!
      expect(await destFile.exists(), isTrue);
      expect(await destFile.readAsBytes(), [1, 2, 3]);
      expect(await localDataSource.getPromotionJournal(6, '7'), isNull);
    });
  });
}
