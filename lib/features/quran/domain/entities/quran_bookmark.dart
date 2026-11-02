import 'package:equatable/equatable.dart';
import 'ayah_id.dart';

/// Represents a bookmarked Quranic Ayah with its creation timestamp, optional page snapshot,
/// custom user-defined name/label, and custom accent color.
/// Canonical text, Surah names, and QCF glyphs are resolved dynamically and not persisted.
class QuranBookmark extends Equatable {
  final AyahId ayahId;
  final DateTime createdAt;
  final int? pageNumber;
  final String? name;
  final int? colorCode;

  const QuranBookmark({
    required this.ayahId,
    required this.createdAt,
    this.pageNumber,
    this.name,
    this.colorCode,
  });

  QuranBookmark copyWith({
    AyahId? ayahId,
    DateTime? createdAt,
    int? pageNumber,
    String? name,
    int? colorCode,
  }) {
    return QuranBookmark(
      ayahId: ayahId ?? this.ayahId,
      createdAt: createdAt ?? this.createdAt,
      pageNumber: pageNumber ?? this.pageNumber,
      name: name ?? this.name,
      colorCode: colorCode ?? this.colorCode,
    );
  }

  @override
  List<Object?> get props => [ayahId, createdAt, pageNumber, name, colorCode];
}
