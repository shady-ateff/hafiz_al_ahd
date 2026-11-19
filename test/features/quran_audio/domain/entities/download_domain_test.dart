import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_recovery_action.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_resource_identity.dart';

void main() {
  group('AudioDownload Status Separation & Persistence Whitelist (QA.5 B1)', () {
    test('strictly whitelists persisted statuses in SQLite table', () {
      const expectedPersisted = {
        AudioDownloadStatus.downloading,
        AudioDownloadStatus.paused,
        AudioDownloadStatus.verifying,
        AudioDownloadStatus.completed,
        AudioDownloadStatus.failed,
        AudioDownloadStatus.cancelled,
      };

      expect(AudioDownloadStatus.persistedStatuses, equals(expectedPersisted));

      for (final status in expectedPersisted) {
        expect(status.isPersisted, isTrue);
      }

      expect(AudioDownloadStatus.idle.isPersisted, isFalse);
      expect(AudioDownloadStatus.preparing.isPersisted, isFalse);
      expect(AudioDownloadStatus.promoting.isPersisted, isFalse);
      expect(AudioDownloadStatus.missing.isPersisted, isFalse);
      expect(AudioDownloadStatus.corrupted.isPersisted, isFalse);
    });

    test('verifies that notDownloaded and queued are NOT in AudioDownloadStatus enum', () {
      final enumNames = AudioDownloadStatus.values.map((e) => e.name).toList();
      expect(enumNames.contains('notDownloaded'), isFalse);
      expect(enumNames.contains('queued'), isFalse);
    });

    test('AudioDownloadDisplayStatus derives UI presentation states cleanly', () {
      expect(
        AudioDownloadDisplayStatus.fromPersisted(null),
        AudioDownloadDisplayStatus.notDownloaded,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.idle),
        AudioDownloadDisplayStatus.notDownloaded,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.missing),
        AudioDownloadDisplayStatus.notDownloaded,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.downloading),
        AudioDownloadDisplayStatus.downloading,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.paused),
        AudioDownloadDisplayStatus.paused,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.verifying),
        AudioDownloadDisplayStatus.verifying,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.promoting),
        AudioDownloadDisplayStatus.verifying,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.completed),
        AudioDownloadDisplayStatus.completed,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.failed),
        AudioDownloadDisplayStatus.failed,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.corrupted),
        AudioDownloadDisplayStatus.failed,
      );
      expect(
        AudioDownloadDisplayStatus.fromPersisted(AudioDownloadStatus.cancelled),
        AudioDownloadDisplayStatus.cancelled,
      );
    });
  });

  group('AudioDownload Entity & Invariants (QA.5 2.A)', () {
    final now = DateTime(2026, 11, 19, 12, 0, 0);

    test('creates valid AudioDownload in downloading state', () {
      final download = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        tempRelativePath: '.staging/reciter_7_surah_001.tmp',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 500000,
        expectedSizeBytes: 1000000,
        etag: '"strong-etag-123"',
        lastModified: 'Wed, 21 Oct 2026 07:28:00 GMT',
        downloadedAt: now,
      );

      expect(download.surahNumber, 1);
      expect(download.reciterId, '7');
      expect(download.localRelativePath, 'reciter_7/surah_001.mp3');
      expect(download.tempRelativePath, '.staging/reciter_7_surah_001.tmp');
      expect(download.status, AudioDownloadStatus.downloading);
      expect(download.actualSizeBytes, 500000);
      expect(download.expectedSizeBytes, 1000000);
      expect(download.transferIntegrityVerified, isFalse);
      expect(download.etag, '"strong-etag-123"');
      expect(download.lastModified, 'Wed, 21 Oct 2026 07:28:00 GMT');
      expect(download.downloadedAt, now);
      expect(download.completedAt, isNull);
      expect(download.isPlayable, isFalse);
    });

    test('validates Surah number boundary strictly (1..114)', () {
      expect(
        () => AudioDownload(
          surahNumber: 0,
          reciterId: '7',
          localRelativePath: 'reciter_7/0.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 115,
          reciterId: '7',
          localRelativePath: 'reciter_7/115.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      final surah1 = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/1.mp3',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 0,
      );
      expect(surah1.surahNumber, 1);

      final surah114 = AudioDownload(
        surahNumber: 114,
        reciterId: '7',
        localRelativePath: 'reciter_7/114.mp3',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 0,
      );
      expect(surah114.surahNumber, 114);
    });

    test('rejects empty or whitespace reciterId', () {
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '',
          localRelativePath: 'reciter/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '   ',
          localRelativePath: 'reciter/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects path traversal in reciterId, localRelativePath, and tempRelativePath', () {
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '../7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7/sub',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: '../../secret.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: '/absolute/file.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: r'\windows\absolute.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          tempRelativePath: '../traversal.tmp',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );
    });

    test('enforces strict completed state invariants', () {
      // Completed with 0 bytes is strictly rejected
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 0,
        ),
        throwsArgumentError,
      );

      // Completed with negative bytes is rejected
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: -100,
        ),
        throwsArgumentError,
      );

      // Completed with actualSizeBytes != expectedSizeBytes is rejected
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 500000,
          expectedSizeBytes: 1000000,
        ),
        throwsArgumentError,
      );

      // Non-completed with non-null completedAt is rejected
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 500000,
          completedAt: DateTime.now(),
        ),
        throwsArgumentError,
      );
    });

    test('enforces transferIntegrityVerified invariants and distinguishes legacy v1', () {
      // transferIntegrityVerified cannot be true if status is not completed
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.downloading,
          actualSizeBytes: 500000,
          transferIntegrityVerified: true,
          sha256: 'a' * 64,
        ),
        throwsArgumentError,
      );

      // transferIntegrityVerified cannot be true if sha256 is null or empty
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 500000,
          transferIntegrityVerified: true,
          sha256: null,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: 'reciter_7/1.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 500000,
          transferIntegrityVerified: true,
          sha256: '   ',
        ),
        throwsArgumentError,
      );

      // Legacy v1 completed asset: valid without transfer integrity verification
      final legacyV1 = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/1.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 500000,
        sha256: 'legacy-fingerprint-only',
        transferIntegrityVerified: false,
      );
      expect(legacyV1.isPlayable, isTrue);
      expect(legacyV1.transferIntegrityVerified, isFalse);

      // Modern verified asset: completed with transfer integrity verified
      final verifiedAsset = AudioDownload(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/1.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 500000,
        sha256: 'a' * 64,
        transferIntegrityVerified: true,
      );
      expect(verifiedAsset.isPlayable, isTrue);
      expect(verifiedAsset.transferIntegrityVerified, isTrue);
    });

    test('verifies status helper getters correctly', () {
      expect(AudioDownloadStatus.completed.isCompleted, isTrue);
      expect(AudioDownloadStatus.downloading.isCompleted, isFalse);

      expect(AudioDownloadStatus.downloading.isActive, isTrue);
      expect(AudioDownloadStatus.verifying.isActive, isTrue);
      expect(AudioDownloadStatus.promoting.isActive, isTrue);
      expect(AudioDownloadStatus.preparing.isActive, isTrue);
      expect(AudioDownloadStatus.completed.isActive, isFalse);
      expect(AudioDownloadStatus.failed.isActive, isFalse);

      expect(AudioDownloadStatus.completed.isTerminal, isTrue);
      expect(AudioDownloadStatus.failed.isTerminal, isTrue);
      expect(AudioDownloadStatus.cancelled.isTerminal, isTrue);
      expect(AudioDownloadStatus.downloading.isTerminal, isFalse);

      expect(AudioDownloadStatus.downloading.isPausable, isTrue);
      expect(AudioDownloadStatus.paused.isPausable, isFalse);

      expect(AudioDownloadStatus.paused.isResumable, isTrue);
      expect(AudioDownloadStatus.failed.isResumable, isTrue);
      expect(AudioDownloadStatus.cancelled.isResumable, isTrue);
      expect(AudioDownloadStatus.downloading.isResumable, isFalse);
    });

    test('copyWith preserves immutable downloadedAt and resets completedAt on status change', () {
      final initialDate = DateTime(2026, 11, 1, 10, 0, 0);
      final completionDate = DateTime(2026, 11, 1, 10, 5, 0);

      final original = AudioDownload(
        surahNumber: 2,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_002.mp3',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 1000,
        downloadedAt: initialDate,
      );

      final completed = original.copyWith(
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 5000000,
        transferIntegrityVerified: true,
        sha256: 'abcdef1234567890',
        completedAt: completionDate,
      );

      expect(completed.downloadedAt, initialDate);
      expect(completed.completedAt, completionDate);
      expect(completed.transferIntegrityVerified, isTrue);
      expect(completed.isPlayable, isTrue);

      // Transitioning away from completed nullifies completedAt and transferIntegrityVerified
      final failed = completed.copyWith(
        status: AudioDownloadStatus.failed,
        transferIntegrityVerified: false,
      );
      expect(failed.completedAt, isNull);
      expect(failed.status, AudioDownloadStatus.failed);
      expect(failed.isPlayable, isFalse);
    });
  });

  group('DownloadProgress Entity & Calculations', () {
    test('initial factory produces idle status with 0 bytes and notDownloaded display status', () {
      final progress = DownloadProgress.initial(
        surahNumber: 1,
        reciterId: '7',
        expectedTotalBytes: 500000,
      );

      expect(progress.surahNumber, 1);
      expect(progress.reciterId, '7');
      expect(progress.status, AudioDownloadStatus.idle);
      expect(progress.displayStatus, AudioDownloadDisplayStatus.notDownloaded);
      expect(progress.downloadedBytes, 0);
      expect(progress.expectedTotalBytes, 500000);
      expect(progress.progressRatio, 0.0);
      expect(progress.progressPercentage, 0);
      expect(progress.isDownloading, isFalse);
      expect(progress.isCompleted, isFalse);
      expect(progress.isIndeterminate, isFalse);
    });

    test('indeterminate progress handles null or <= 0 expectedTotalBytes safely', () {
      final indeterminate1 = DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 150000,
        expectedTotalBytes: null,
      );

      expect(indeterminate1.isIndeterminate, isTrue);
      expect(indeterminate1.progressRatio, 0.0);
      expect(indeterminate1.progressPercentage, 0);

      final indeterminate2 = DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 150000,
        expectedTotalBytes: 0,
      );

      expect(indeterminate2.isIndeterminate, isTrue);
      expect(indeterminate2.progressRatio, 0.0);
      expect(indeterminate2.progressPercentage, 0);
    });

    test('computes exact progress ratio and clamps between 0.0 and 1.0', () {
      final half = DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 500000,
        expectedTotalBytes: 1000000,
      );

      expect(half.progressRatio, 0.5);
      expect(half.progressPercentage, 50);

      final overflow = DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 1200000,
        expectedTotalBytes: 1000000,
      );

      expect(overflow.progressRatio, 1.0);
      expect(overflow.progressPercentage, 100);
    });

    test('copyWith updates progress telemetry accurately', () {
      final initial = DownloadProgress.initial(
        surahNumber: 18,
        reciterId: '7',
        expectedTotalBytes: 2000000,
      );

      final updated = initial.copyWith(
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 1000000,
        downloadSpeedBytesPerSecond: 250000.0,
        estimatedTimeRemaining: const Duration(seconds: 4),
      );

      expect(updated.status, AudioDownloadStatus.downloading);
      expect(updated.displayStatus, AudioDownloadDisplayStatus.downloading);
      expect(updated.downloadedBytes, 1000000);
      expect(updated.progressPercentage, 50);
      expect(updated.downloadSpeedBytesPerSecond, 250000.0);
      expect(updated.estimatedTimeRemaining, const Duration(seconds: 4));
      expect(updated.isDownloading, isTrue);
    });
  });

  group('HttpStrongValidator Classification (RFC 9110 §8.8.2.2 & §8.8.3)', () {
    test('isStrongEtag classifies strong and weak ETags correctly', () {
      expect(HttpStrongValidator.isStrongEtag('"strong-12345"'), isTrue);
      expect(HttpStrongValidator.isStrongEtag('""'), isTrue); // Empty quoted tag

      // Weak tags strictly rejected
      expect(HttpStrongValidator.isStrongEtag('W/"weak-12345"'), isFalse);
      expect(HttpStrongValidator.isStrongEtag('w/"weak-12345"'), isFalse);

      // Unquoted arbitrary strings strictly rejected
      expect(HttpStrongValidator.isStrongEtag('unquoted-tag'), isFalse);
      expect(HttpStrongValidator.isStrongEtag(null), isFalse);
      expect(HttpStrongValidator.isStrongEtag(''), isFalse);
    });

    test('isStrongLastModified requires Date - Last-Modified >= 1 second using origin clock', () {
      // 5 seconds difference -> Strong
      expect(
        HttpStrongValidator.isStrongLastModified(
          lastModifiedHeader: 'Wed, 21 Oct 2026 07:28:00 GMT',
          originDateHeader: 'Wed, 21 Oct 2026 07:28:05 GMT',
        ),
        isTrue,
      );

      // Exactly 1 second difference -> Strong
      expect(
        HttpStrongValidator.isStrongLastModified(
          lastModifiedHeader: 'Wed, 21 Oct 2026 07:28:00 GMT',
          originDateHeader: 'Wed, 21 Oct 2026 07:28:01 GMT',
        ),
        isTrue,
      );

      // 0 seconds difference -> WEAK (not strong)
      expect(
        HttpStrongValidator.isStrongLastModified(
          lastModifiedHeader: 'Wed, 21 Oct 2026 07:28:00 GMT',
          originDateHeader: 'Wed, 21 Oct 2026 07:28:00 GMT',
        ),
        isFalse,
      );

      // Missing origin Date header -> WEAK (cannot verify)
      expect(
        HttpStrongValidator.isStrongLastModified(
          lastModifiedHeader: 'Wed, 21 Oct 2026 07:28:00 GMT',
          originDateHeader: null,
        ),
        isFalse,
      );
    });
  });

  group('DownloadResourceIdentity Contract (Rev 7 B1-5 & QA.5 2.B)', () {
    test('confirms identical resource when URL, surah, reciter, and strong ETag match', () {
      const identity = DownloadResourceIdentity(
        requestUrl: 'https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3',
        recordedUrl: 'https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3',
        surahNumber: 1,
        recordedSurahNumber: 1,
        reciterId: '7',
        recordedReciterId: '7',
        responseStrongValidator: '"strong-etag-12345"',
        recordedStrongValidator: '"strong-etag-12345"',
      );

      expect(identity.isIdenticalResource, isTrue);
    });

    test('rejects identity if validator is a weak ETag even if matching', () {
      const identity = DownloadResourceIdentity(
        requestUrl: 'https://download.quranicaudio.com/1.mp3',
        recordedUrl: 'https://download.quranicaudio.com/1.mp3',
        surahNumber: 1,
        recordedSurahNumber: 1,
        reciterId: '7',
        recordedReciterId: '7',
        responseStrongValidator: 'W/"weak-etag-12345"',
        recordedStrongValidator: 'W/"weak-etag-12345"',
      );

      expect(identity.isIdenticalResource, isFalse);
    });

    test('rejects identity if validator is an unquoted string', () {
      const identity = DownloadResourceIdentity(
        requestUrl: 'https://download.quranicaudio.com/1.mp3',
        recordedUrl: 'https://download.quranicaudio.com/1.mp3',
        surahNumber: 1,
        recordedSurahNumber: 1,
        reciterId: '7',
        recordedReciterId: '7',
        responseStrongValidator: 'raw_unquoted_string',
        recordedStrongValidator: 'raw_unquoted_string',
      );

      expect(identity.isIdenticalResource, isFalse);
    });

    test('rejects identity if requestUrl, surah, or reciter differs', () {
      const diffUrl = DownloadResourceIdentity(
        requestUrl: 'https://cdn2.quranicaudio.com/1.mp3',
        recordedUrl: 'https://cdn1.quranicaudio.com/1.mp3',
        surahNumber: 1,
        recordedSurahNumber: 1,
        reciterId: '7',
        recordedReciterId: '7',
        responseStrongValidator: '"strong-etag-12345"',
        recordedStrongValidator: '"strong-etag-12345"',
      );
      expect(diffUrl.isIdenticalResource, isFalse);

      const diffSurah = DownloadResourceIdentity(
        requestUrl: 'https://download.quranicaudio.com/1.mp3',
        recordedUrl: 'https://download.quranicaudio.com/1.mp3',
        surahNumber: 2,
        recordedSurahNumber: 1,
        reciterId: '7',
        recordedReciterId: '7',
        responseStrongValidator: '"strong-etag-12345"',
        recordedStrongValidator: '"strong-etag-12345"',
      );
      expect(diffSurah.isIdenticalResource, isFalse);

      const diffReciter = DownloadResourceIdentity(
        requestUrl: 'https://download.quranicaudio.com/1.mp3',
        recordedUrl: 'https://download.quranicaudio.com/1.mp3',
        surahNumber: 1,
        recordedSurahNumber: 1,
        reciterId: '8',
        recordedReciterId: '7',
        responseStrongValidator: '"strong-etag-12345"',
        recordedStrongValidator: '"strong-etag-12345"',
      );
      expect(diffReciter.isIdenticalResource, isFalse);
    });
  });

  group('Startup Recovery Classification & Algorithm (Rev 7 B1-4 & QA.5 2.C)', () {
    final sampleRecord = AudioDownload(
      surahNumber: 1,
      reciterId: '7',
      localRelativePath: 'reciter_7/surah_001.mp3',
      tempRelativePath: '.staging/reciter_7_surah_001.tmp',
      status: AudioDownloadStatus.downloading,
      actualSizeBytes: 500000,
      expectedSizeBytes: 1000000,
    );

    test('Rule 1: Journal presence triggers journalRecoveryRequired regardless of files', () {
      final result = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 500000,
        hasStrongValidator: true,
        hasPendingJournal: true,
        resourceIdentityMatches: true,
      );

      expect(result, StartupRecoveryResult.journalRecoveryRequired);
    });

    test('Rule 2: Missing or empty staging file requires restart', () {
      final resultMissing = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );
      expect(resultMissing, StartupRecoveryResult.restartRequired);

      final resultEmpty = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 0,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );
      expect(resultEmpty, StartupRecoveryResult.restartRequired);
    });

    test('Rule 3: On-disk byte length mismatch with DB actualSizeBytes requires restart', () {
      final resultMismatch = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 499999,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );

      expect(resultMismatch, StartupRecoveryResult.restartRequired);
    });

    test('Rule 4: Mismatched resource identity or weak/missing validator requires restart', () {
      final resultIdentityMismatch = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 500000,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: false,
      );
      expect(resultIdentityMismatch, StartupRecoveryResult.restartRequired);

      final resultNoStrongValidator = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 500000,
        hasStrongValidator: false,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );
      expect(resultNoStrongValidator, StartupRecoveryResult.restartRequired);
    });

    test('Rule 5A: Staging length overshoot beyond expected total requires restart', () {
      final overshootRecord = sampleRecord.copyWith(
        actualSizeBytes: 1200000,
        expectedSizeBytes: 1000000,
      );

      final result = evaluateStartupRecovery(
        dbRecord: overshootRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 1200000,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );

      expect(result, StartupRecoveryResult.restartRequired);
    });

    test('Rule 5B: Staging length strictly equals expected total requires verification, not re-download', () {
      final completedRecord = sampleRecord.copyWith(
        actualSizeBytes: 1000000,
        expectedSizeBytes: 1000000,
      );

      final result = evaluateStartupRecovery(
        dbRecord: completedRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 1000000,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );

      expect(result, StartupRecoveryResult.verificationRequired);
    });

    test('Rule 6: Valid partial transfer with matching validator permits Range resume', () {
      final result = evaluateStartupRecovery(
        dbRecord: sampleRecord,
        stagingFileExists: true,
        stagingPhysicalLength: 500000,
        hasStrongValidator: true,
        hasPendingJournal: false,
        resourceIdentityMatches: true,
      );

      expect(result, StartupRecoveryResult.canResume);
    });

    test('resolveRecoveryAction enforces rigorous physical checks for alreadyCompleted (QA.5 2.C)', () {
      final completedRecord = sampleRecord.copyWith(
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 1000000,
        expectedSizeBytes: 1000000,
      );

      // 1. Valid destination file matching DB -> alreadyCompleted
      final validResult = resolveRecoveryAction(
        dbRecord: completedRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: false,
        hasPendingJournal: false,
        resourceIdentityMatches: false,
        destinationFileExists: true,
        destinationPhysicalLength: 1000000,
      );
      expect(validResult, StartupRecoveryResult.alreadyCompleted);

      // 2. Destination file missing on disk -> restartRequired
      final missingResult = resolveRecoveryAction(
        dbRecord: completedRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: false,
        hasPendingJournal: false,
        resourceIdentityMatches: false,
        destinationFileExists: false,
      );
      expect(missingResult, StartupRecoveryResult.restartRequired);

      // 3. Destination file empty (0 bytes) -> restartRequired
      final emptyResult = resolveRecoveryAction(
        dbRecord: completedRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: false,
        hasPendingJournal: false,
        resourceIdentityMatches: false,
        destinationFileExists: true,
        destinationPhysicalLength: 0,
      );
      expect(emptyResult, StartupRecoveryResult.restartRequired);

      // 4. Destination file truncated (size mismatch) -> restartRequired
      final truncatedResult = resolveRecoveryAction(
        dbRecord: completedRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: false,
        hasPendingJournal: false,
        resourceIdentityMatches: false,
        destinationFileExists: true,
        destinationPhysicalLength: 999999,
      );
      expect(truncatedResult, StartupRecoveryResult.restartRequired);

      // 5. Journal precedence: even if destination file is valid, journal requires recovery
      final journalPrecedenceResult = resolveRecoveryAction(
        dbRecord: completedRecord,
        stagingFileExists: false,
        stagingPhysicalLength: null,
        hasStrongValidator: false,
        hasPendingJournal: true,
        resourceIdentityMatches: false,
        destinationFileExists: true,
        destinationPhysicalLength: 1000000,
      );
      expect(journalPrecedenceResult, StartupRecoveryResult.journalRecoveryRequired);
    });
  });
}
