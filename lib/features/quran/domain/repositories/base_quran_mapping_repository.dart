import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../entities/ayah_id.dart';
import '../entities/ayah_segment.dart';
import '../entities/quran_ayah.dart';
import '../entities/quran_line_mapping.dart';
import '../entities/quran_word.dart';
import '../entities/word_location.dart';

/// Repository contract responsible for providing interactive word-level mappings,
/// segment distributions, and Ayah metadata from the Mushaf mapping dataset.
abstract class BaseQuranMappingRepository {
  /// Initializes and caches the mapping dataset in memory once.
  Future<Either<Failure, void>> init();

  /// Retrieves the line-by-line interactive mappings for a specific physical page (1..604).
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(int pageNumber);

  /// Retrieves the full Ayah information by its [AyahId].
  Future<Either<Failure, QuranAyah>> getAyah(AyahId ayahId);

  /// Retrieves the ordered line segments for a specific Ayah across its physical lines.
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(AyahId ayahId);

  /// Resolves an individual word by its precise location.
  Future<Either<Failure, QuranWord>> getWord(WordLocation location);
}

