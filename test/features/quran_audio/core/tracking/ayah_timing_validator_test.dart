import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_timing_validator.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';

void main() {
  group('AyahTimingValidator', () {
    const validator = AyahTimingValidator();

    test('validates and preserves sorted contiguous timings', () {
      final raw = [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5000, timestampTo: 10000),
      ];

      final result = validator.validateAndSanitize(raw);

      expect(result.isValid, isTrue);
      expect(result.hasOverlaps, isFalse);
      expect(result.hasGaps, isFalse);
      expect(result.issues, isEmpty);
      expect(result.sanitizedTimings.length, 2);
    });

    test('re-sorts out-of-order timings by timestampFrom', () {
      final outOfOrder = [
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5000, timestampTo: 10000),
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
      ];

      final result = validator.validateAndSanitize(outOfOrder);

      expect(result.isValid, isTrue);
      expect(result.sanitizedTimings[0].ayahNumber, 1);
      expect(result.sanitizedTimings[1].ayahNumber, 2);
    });

    test('detects and logs overlaps', () {
      final overlapping = [
        AyahTiming(surahNumber: 2, ayahNumber: 25, timestampFrom: 400000, timestampTo: 451590),
        AyahTiming(surahNumber: 2, ayahNumber: 26, timestampFrom: 412950, timestampTo: 480000),
      ];

      final result = validator.validateAndSanitize(overlapping);

      expect(result.hasOverlaps, isTrue);
      expect(result.issues.first, contains('Overlap detected between Ayah 2:25 and 2:26'));
    });

    test('returns invalid for empty list', () {
      final result = validator.validateAndSanitize([]);

      expect(result.isValid, isFalse);
      expect(result.sanitizedTimings, isEmpty);
    });
  });
}
