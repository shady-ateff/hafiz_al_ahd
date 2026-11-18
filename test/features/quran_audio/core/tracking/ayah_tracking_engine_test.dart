import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/tracking/ayah_tracking_engine.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';

void main() {
  group('AyahTrackingEngine', () {
    late AyahTrackingEngine engine;
    late List<AyahTiming> sampleTimings;

    setUp(() {
      engine = AyahTrackingEngine(gapGracePeriodMs: 1000);

      // Al-Fatihah simulated timings (contiguous)
      sampleTimings = [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 6000),
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 6000, timestampTo: 11000),
        AyahTiming(surahNumber: 1, ayahNumber: 3, timestampFrom: 11000, timestampTo: 16000),
        AyahTiming(surahNumber: 1, ayahNumber: 4, timestampFrom: 16000, timestampTo: 21000),
        AyahTiming(surahNumber: 1, ayahNumber: 5, timestampFrom: 21000, timestampTo: 27000),
        AyahTiming(surahNumber: 1, ayahNumber: 6, timestampFrom: 27000, timestampTo: 33000),
        AyahTiming(surahNumber: 1, ayahNumber: 7, timestampFrom: 33000, timestampTo: 46000),
      ];

      engine.setTimings(sampleTimings);
    });

    test('resolves exact Ayah based on position in contiguous recitation', () {
      expect(engine.resolveAyahAtPosition(0)?.ayahNumber, 1);
      expect(engine.resolveAyahAtPosition(3000)?.ayahNumber, 1);
      expect(engine.resolveAyahAtPosition(5999)?.ayahNumber, 1);
      expect(engine.resolveAyahAtPosition(6000)?.ayahNumber, 2);
      expect(engine.resolveAyahAtPosition(10000)?.ayahNumber, 2);
      expect(engine.resolveAyahAtPosition(11000)?.ayahNumber, 3);
      expect(engine.resolveAyahAtPosition(35000)?.ayahNumber, 7);
      expect(engine.resolveAyahAtPosition(46000)?.ayahNumber, 7);
    });

    test('returns null for position before first Ayah', () {
      final introTimings = [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 3000, timestampTo: 8000),
      ];
      engine.setTimings(introTimings);

      expect(engine.resolveAyahAtPosition(1000), isNull);
      expect(engine.resolveAyahAtPosition(3000)?.ayahNumber, 1);
    });

    test('retains Ayah highlight during recitation gaps within grace period', () {
      final gappedTimings = [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
        // 800 ms silent gap between 5000 and 5800
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 5800, timestampTo: 10000),
      ];
      engine.setTimings(gappedTimings);

      // In gap (5400 ms): 400 ms past Ayah 1 -> within 1000 ms grace period
      final inGap = engine.resolveAyahAtPosition(5400);
      expect(inGap?.ayahNumber, 1);

      // At start of Ayah 2
      expect(engine.resolveAyahAtPosition(5800)?.ayahNumber, 2);
    });

    test('clears highlight if silent gap exceeds grace period', () {
      final largeGapTimings = [
        AyahTiming(surahNumber: 1, ayahNumber: 1, timestampFrom: 0, timestampTo: 5000),
        // 2500 ms gap between 5000 and 7500
        AyahTiming(surahNumber: 1, ayahNumber: 2, timestampFrom: 7500, timestampTo: 12000),
      ];
      engine.setTimings(largeGapTimings);

      // 6500 ms is 1500 ms past end of Ayah 1 (exceeds 1000 ms grace period)
      expect(engine.resolveAyahAtPosition(6500), isNull);
    });

    test('handles overlapping intervals with forward progression guard (Abdul Basit anomaly simulation)', () {
      // Simulating observed anomaly: Ayah 25 ends at 451,590, but Ayah 26 starts at 412,950
      final overlappingTimings = [
        AyahTiming(surahNumber: 2, ayahNumber: 24, timestampFrom: 380000, timestampTo: 400000),
        AyahTiming(surahNumber: 2, ayahNumber: 25, timestampFrom: 400000, timestampTo: 451590),
        AyahTiming(surahNumber: 2, ayahNumber: 26, timestampFrom: 412950, timestampTo: 480000),
      ];
      engine.setTimings(overlappingTimings);

      // 1. Play before overlap
      expect(engine.resolveAyahAtPosition(390000)?.ayahNumber, 24);
      expect(engine.resolveAyahAtPosition(405000)?.ayahNumber, 25);

      // 2. Play enters overlap window (420000): Ayah 26 has started, progression selects 26
      expect(engine.resolveAyahAtPosition(420000)?.ayahNumber, 26);

      // 3. During overlap (430000): forward progression ensures we don't jump backward to 25
      expect(engine.resolveAyahAtPosition(430000)?.ayahNumber, 26);
    });

    test('backward seeking resets progression guard and resolves accurately', () {
      engine.setTimings(sampleTimings);

      // Play up to Ayah 5 (25000 ms)
      expect(engine.resolveAyahAtPosition(25000)?.ayahNumber, 5);

      // User seeks backward to Ayah 2 (8000 ms) with explicit seek
      final afterSeek = engine.resolveAyahAtPosition(8000, isExplicitSeek: true);
      expect(afterSeek?.ayahNumber, 2);

      // User seeks backward implicitly (> 500 ms jump backward)
      expect(engine.resolveAyahAtPosition(2000)?.ayahNumber, 1);
    });
  });
}
