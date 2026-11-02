import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_bookmark.dart';

/// Serializable data model for [QuranBookmark].
/// Stores only the primary identifier [ayahId], creation timestamp [createdAt],
/// optional snapshot [pageNumber], custom [name], and custom [colorCode].
/// Does not persist redundant text, surah names, or QCF glyphs.
class QuranBookmarkModel extends QuranBookmark {
  const QuranBookmarkModel({
    required super.ayahId,
    required super.createdAt,
    super.pageNumber,
    super.name,
    super.colorCode,
  });

  factory QuranBookmarkModel.fromEntity(QuranBookmark entity) {
    return QuranBookmarkModel(
      ayahId: entity.ayahId,
      createdAt: entity.createdAt,
      pageNumber: entity.pageNumber,
      name: entity.name,
      colorCode: entity.colorCode,
    );
  }

  factory QuranBookmarkModel.fromJson(Map<String, dynamic> json) {
    final rawAyahId = json['ayah_id'] ?? json['ayahId'];
    if (rawAyahId == null) {
      throw const FormatException('Missing required field: ayah_id');
    }

    final rawCreatedAt = json['created_at'] ?? json['createdAt'];
    if (rawCreatedAt == null) {
      throw const FormatException('Missing required field: created_at');
    }

    final pageNumber =
        json['page_number'] as int? ?? json['pageNumber'] as int?;
    final name = json['name'] as String?;
    final colorCode =
        json['color_code'] as int? ?? json['colorCode'] as int?;

    return QuranBookmarkModel(
      ayahId: AyahId.fromString(rawAyahId.toString()),
      createdAt: DateTime.parse(rawCreatedAt.toString()),
      pageNumber: pageNumber,
      name: name,
      colorCode: colorCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ayah_id': ayahId.formatted,
      'created_at': createdAt.toIso8601String(),
      if (pageNumber != null) 'page_number': pageNumber,
      if (name != null) 'name': name,
      if (colorCode != null) 'color_code': colorCode,
    };
  }
}
