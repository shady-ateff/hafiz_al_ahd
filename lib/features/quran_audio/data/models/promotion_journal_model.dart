import '../../domain/entities/promotion_journal_entry.dart';

/// Data model for [PromotionJournalEntry] supporting SQLite and JSON serialization.
class PromotionJournalModel extends PromotionJournalEntry {
  PromotionJournalModel({
    required super.surahNumber,
    required super.reciterId,
    required super.stagingPath,
    required super.stagingSha256,
    required super.destinationPath,
    super.backupPath,
    super.previousSha256,
    super.quarantinePath,
    super.quarantineSha256,
    required super.promotionState,
    super.createdAt,
  });

  factory PromotionJournalModel.fromEntity(PromotionJournalEntry entity) {
    return PromotionJournalModel(
      surahNumber: entity.surahNumber,
      reciterId: entity.reciterId,
      stagingPath: entity.stagingPath,
      stagingSha256: entity.stagingSha256,
      destinationPath: entity.destinationPath,
      backupPath: entity.backupPath,
      previousSha256: entity.previousSha256,
      quarantinePath: entity.quarantinePath,
      quarantineSha256: entity.quarantineSha256,
      promotionState: entity.promotionState,
      createdAt: entity.createdAt,
    );
  }

  factory PromotionJournalModel.fromJson(Map<String, dynamic> json) {
    final stateStr = json['promotion_state'] as String? ?? 'idle';
    final state = PromotionJournalState.fromDbValue(stateStr);

    final createdAtRaw = json['created_at'];
    final createdAt = createdAtRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAtRaw)
        : (createdAtRaw != null
            ? DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now()
            : DateTime.now());

    return PromotionJournalModel(
      surahNumber: (json['surah_number'] as num?)?.toInt() ?? 1,
      reciterId: json['reciter_id']?.toString() ?? '',
      stagingPath: json['staging_path'] as String? ?? '',
      stagingSha256: json['staging_sha256'] as String? ?? '',
      destinationPath: json['destination_path'] as String? ?? '',
      backupPath: json['backup_path'] as String?,
      previousSha256: json['previous_sha256'] as String?,
      quarantinePath: json['quarantine_path'] as String?,
      quarantineSha256: json['quarantine_sha256'] as String?,
      promotionState: state,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'surah_number': surahNumber,
        'reciter_id': reciterId,
        'staging_path': stagingPath,
        'staging_sha256': stagingSha256,
        'destination_path': destinationPath,
        'backup_path': backupPath,
        'previous_sha256': previousSha256,
        'quarantine_path': quarantinePath,
        'quarantine_sha256': quarantineSha256,
        'promotion_state': promotionState.dbValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Map<String, dynamic> toJson() => toDbMap();
}
