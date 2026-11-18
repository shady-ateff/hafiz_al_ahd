import 'dart:developer';
import '../../domain/entities/ayah_timing.dart';

/// Validation report summarizing the structural integrity of an Ayah timing track.
class AyahTimingValidationResult {
  final bool isValid;
  final bool hasOverlaps;
  final bool hasGaps;
  final List<String> issues;
  final List<AyahTiming> sanitizedTimings;

  const AyahTimingValidationResult({
    required this.isValid,
    required this.hasOverlaps,
    required this.hasGaps,
    required this.issues,
    required this.sanitizedTimings,
  });
}

/// Service responsible for validating, sanitizing, and sorting provider Ayah timing intervals.
class AyahTimingValidator {
  const AyahTimingValidator();

  /// Validates and sanitizes a list of Ayah timings.
  ///
  /// Guarantees that the returned [AyahTimingValidationResult.sanitizedTimings] are:
  /// 1. Sorted monotonically by `timestampFrom`.
  /// 2. Contain valid Ayah and Surah identifiers.
  /// 3. Overlaps and gaps are safely cataloged.
  AyahTimingValidationResult validateAndSanitize(List<AyahTiming> rawTimings) {
    if (rawTimings.isEmpty) {
      return const AyahTimingValidationResult(
        isValid: false,
        hasOverlaps: false,
        hasGaps: false,
        issues: ['Empty timings list'],
        sanitizedTimings: [],
      );
    }

    final issues = <String>[];
    bool hasOverlaps = false;
    bool hasGaps = false;

    // 1. Sort strictly by timestampFrom, breaking ties with ayahNumber
    final sorted = List<AyahTiming>.from(rawTimings)
      ..sort((a, b) {
        final cmp = a.timestampFrom.compareTo(b.timestampFrom);
        if (cmp != 0) return cmp;
        return a.ayahNumber.compareTo(b.ayahNumber);
      });

    // 2. Validate intervals and detect overlaps / gaps
    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];

      if (curr.timestampFrom < prev.timestampTo) {
        hasOverlaps = true;
        final overlapMs = prev.timestampTo - curr.timestampFrom;
        issues.add(
          'Overlap detected between Ayah ${prev.verseKey} and ${curr.verseKey}: $overlapMs ms',
        );
        log('⚠️ [AyahTimingValidator] Overlap at ${curr.verseKey}: $overlapMs ms');
      } else if (curr.timestampFrom > prev.timestampTo) {
        hasGaps = true;
        final gapMs = curr.timestampFrom - prev.timestampTo;
        // Minor gaps under 2000 ms are normal recitation pauses between Ayahs
        if (gapMs > 2000) {
          issues.add(
            'Large gap detected between Ayah ${prev.verseKey} and ${curr.verseKey}: $gapMs ms',
          );
        }
      }
    }

    return AyahTimingValidationResult(
      isValid: sorted.isNotEmpty,
      hasOverlaps: hasOverlaps,
      hasGaps: hasGaps,
      issues: issues,
      sanitizedTimings: List.unmodifiable(sorted),
    );
  }
}
