import 'audio_download.dart';

/// Exhaustive classifications for download recovery, crash evaluation, and resumption.
enum StartupRecoveryResult {
  /// No action required.
  none,

  /// Valid partial transfer ready for HTTP 206 Range resumption.
  canResume,

  /// Transfer mismatch, invalid validator, or corrupt length requiring restart from byte 0.
  restartRequired,

  /// Staging file length matches expected total; requires SHA-256 verification and promotion without re-download.
  verificationRequired,

  /// Pending transaction in promotion journal; requires journal recovery engine.
  journalRecoveryRequired,

  /// Download already completed and physical destination file exists and is valid on disk.
  alreadyCompleted,
}

/// Alias for StartupRecoveryResult representing recovery actions.
typedef DownloadRecoveryAction = StartupRecoveryResult;

/// Evaluates an existing interrupted staging file and database record on startup
/// to determine the safe deterministic recovery action without destructive premature deletion.
StartupRecoveryResult evaluateStartupRecovery({
  required AudioDownload dbRecord,
  required bool stagingFileExists,
  required int? stagingPhysicalLength,
  required bool hasStrongValidator,
  required bool hasPendingJournal,
  required bool resourceIdentityMatches,
}) {
  // 1. Journal presence triggers Journal Recovery Engine (NEVER alreadyCompleted)
  if (hasPendingJournal) {
    return StartupRecoveryResult.journalRecoveryRequired;
  }

  // 2. Physical staging file must exist and be non-empty
  if (!stagingFileExists || stagingPhysicalLength == null || stagingPhysicalLength <= 0) {
    return StartupRecoveryResult.restartRequired;
  }

  // 3. Exact byte tally check: on-disk length MUST match DB recorded offset
  if (stagingPhysicalLength != dbRecord.actualSizeBytes) {
    return StartupRecoveryResult.restartRequired;
  }

  // 4. Strict Resource Identity match (URL, reciterId, surahNumber, validator)
  if (!resourceIdentityMatches || !hasStrongValidator) {
    return StartupRecoveryResult.restartRequired;
  }

  // 5. Handling Completed Byte Count vs Overshoot
  if (dbRecord.expectedSizeBytes != null) {
    // Case 5A: Staging length exceeds expected total -> Corrupt transfer
    if (stagingPhysicalLength > dbRecord.expectedSizeBytes!) {
      return StartupRecoveryResult.restartRequired;
    }

    // Case 5B: Staging length strictly equals expected total -> Already fully transferred!
    if (stagingPhysicalLength == dbRecord.expectedSizeBytes!) {
      // Do NOT force re-download! Require full-file verification & promotion.
      return StartupRecoveryResult.verificationRequired;
    }
  }

  // 6. Valid partial transfer ready for HTTP 206 resume
  return StartupRecoveryResult.canResume;
}

/// Resolves overall recovery action considering destination presence, byte validity, and database status.
///
/// Invariant: `alreadyCompleted` is returned ONLY when:
/// 1. Journal is absent (`!hasPendingJournal`).
/// 2. Database status is strictly `completed`.
/// 3. Destination file physically exists on disk and is non-empty (`length > 0`).
/// 4. Destination file physical length equals `dbRecord.actualSizeBytes`.
/// 5. If `dbRecord.expectedSizeBytes` is known, destination length matches expected total.
StartupRecoveryResult resolveRecoveryAction({
  required AudioDownload dbRecord,
  required bool stagingFileExists,
  required int? stagingPhysicalLength,
  required bool hasStrongValidator,
  required bool hasPendingJournal,
  required bool resourceIdentityMatches,
  bool destinationFileExists = false,
  int? destinationPhysicalLength,
}) {
  // 1. Journal presence has absolute precedence over all states
  if (hasPendingJournal) {
    return StartupRecoveryResult.journalRecoveryRequired;
  }

  // 2. Rigorous physical verification for completed records
  if (dbRecord.status == AudioDownloadStatus.completed) {
    final destValid = destinationFileExists &&
        destinationPhysicalLength != null &&
        destinationPhysicalLength > 0 &&
        destinationPhysicalLength == dbRecord.actualSizeBytes &&
        (dbRecord.expectedSizeBytes == null ||
            destinationPhysicalLength == dbRecord.expectedSizeBytes);

    if (destValid) {
      return StartupRecoveryResult.alreadyCompleted;
    }
    // If destination file is missing, empty, or truncated, it CANNOT be considered completed.
    return StartupRecoveryResult.restartRequired;
  }

  // 3. Delegate to staging file evaluation for in-flight/interrupted records
  return evaluateStartupRecovery(
    dbRecord: dbRecord,
    stagingFileExists: stagingFileExists,
    stagingPhysicalLength: stagingPhysicalLength,
    hasStrongValidator: hasStrongValidator,
    hasPendingJournal: hasPendingJournal,
    resourceIdentityMatches: resourceIdentityMatches,
  );
}
