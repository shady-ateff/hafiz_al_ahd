import 'package:equatable/equatable.dart';

/// Lifecycle state of an atomic promotion transaction in the persistent journal.
enum PromotionJournalState {
  /// Promotion initiated, staging file verified, no destination backup/quarantine created yet.
  idle,

  /// Valid existing destination file safely moved to `.bak` backup file.
  backupCreated,

  /// Corrupt existing destination file safely moved to `.quarantine/` file.
  quarantined,

  /// Staging file successfully renamed to destination path, pending DB finalization.
  stagedPromoted;

  String get dbValue {
    switch (this) {
      case PromotionJournalState.idle:
        return 'idle';
      case PromotionJournalState.backupCreated:
        return 'backup_created';
      case PromotionJournalState.quarantined:
        return 'quarantined';
      case PromotionJournalState.stagedPromoted:
        return 'staged_promoted';
    }
  }

  static PromotionJournalState fromDbValue(String value) {
    switch (value) {
      case 'idle':
        return PromotionJournalState.idle;
      case 'backup_created':
        return PromotionJournalState.backupCreated;
      case 'quarantined':
        return PromotionJournalState.quarantined;
      case 'staged_promoted':
        return PromotionJournalState.stagedPromoted;
      default:
        throw ArgumentError.value(value, 'value', 'Unknown promotion state: $value');
    }
  }
}

/// Represents a persistent journal entry tracking an in-flight atomic promotion.
///
/// Guarantees zero data loss across power failures, app crashes, or OS kills during
/// file promotions and destination replacements.
class PromotionJournalEntry extends Equatable {
  /// Surah number (1 to 114).
  final int surahNumber;

  /// Reciter identifier (e.g. "7").
  final String reciterId;

  /// Absolute or relative path to the verified staging file.
  final String stagingPath;

  /// Full-file SHA-256 hex digest of the staging file computed before promotion.
  final String stagingSha256;

  /// Target final destination path for the Surah audio file.
  final String destinationPath;

  /// Temporary backup path if replacing an existing valid destination file.
  final String? backupPath;

  /// SHA-256 hex digest of the previous valid destination file (if any).
  final String? previousSha256;

  /// Temporary quarantine path if replacing an existing corrupt destination file.
  final String? quarantinePath;

  /// SHA-256 hex digest of the quarantined corrupt destination file (if any).
  final String? quarantineSha256;

  /// Current state of the promotion transaction.
  final PromotionJournalState promotionState;

  /// Timestamp when the promotion journal entry was recorded.
  final DateTime createdAt;

  PromotionJournalEntry({
    required this.surahNumber,
    required this.reciterId,
    required this.stagingPath,
    required this.stagingSha256,
    required this.destinationPath,
    this.backupPath,
    this.previousSha256,
    this.quarantinePath,
    this.quarantineSha256,
    required this.promotionState,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'surahNumber must be between 1 and 114',
      );
    }
    if (reciterId.trim().isEmpty) {
      throw ArgumentError.value(reciterId, 'reciterId', 'reciterId cannot be empty');
    }
    if (stagingSha256.trim().isEmpty) {
      throw ArgumentError.value(
        stagingSha256,
        'stagingSha256',
        'stagingSha256 cannot be empty',
      );
    }
  }

  PromotionJournalEntry copyWith({
    int? surahNumber,
    String? reciterId,
    String? stagingPath,
    String? stagingSha256,
    String? destinationPath,
    String? backupPath,
    String? previousSha256,
    String? quarantinePath,
    String? quarantineSha256,
    PromotionJournalState? promotionState,
    DateTime? createdAt,
  }) {
    return PromotionJournalEntry(
      surahNumber: surahNumber ?? this.surahNumber,
      reciterId: reciterId ?? this.reciterId,
      stagingPath: stagingPath ?? this.stagingPath,
      stagingSha256: stagingSha256 ?? this.stagingSha256,
      destinationPath: destinationPath ?? this.destinationPath,
      backupPath: backupPath ?? this.backupPath,
      previousSha256: previousSha256 ?? this.previousSha256,
      quarantinePath: quarantinePath ?? this.quarantinePath,
      quarantineSha256: quarantineSha256 ?? this.quarantineSha256,
      promotionState: promotionState ?? this.promotionState,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        surahNumber,
        reciterId,
        stagingPath,
        stagingSha256,
        destinationPath,
        backupPath,
        previousSha256,
        quarantinePath,
        quarantineSha256,
        promotionState,
        createdAt,
      ];
}
