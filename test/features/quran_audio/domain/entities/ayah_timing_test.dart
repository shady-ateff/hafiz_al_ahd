import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';

void main() {
  group('AyahTiming Entity', () {
    test('creates valid AyahTiming and computes duration', () {
      final timing = AyahTiming(
        surahNumber: 1,
        ayahNumber: 1,
        timestampFrom: 0,
        timestampTo: 6090,
      );

      expect(timing.surahNumber, 1);
      expect(timing.ayahNumber, 1);
      expect(timing.timestampFrom, 0);
      expect(timing.timestampTo, 6090);
      expect(timing.duration, 6090);
      expect(timing.verseKey, '1:1');
      expect(timing.ayahId, AyahId(surahNumber: 1, ayahNumber: 1));
    });

    test('throws ArgumentError on invalid surahNumber', () {
      expect(
        () => AyahTiming(
          surahNumber: 0,
          ayahNumber: 1,
          timestampFrom: 0,
          timestampTo: 1000,
        ),
        throwsArgumentError,
      );

      expect(
        () => AyahTiming(
          surahNumber: 115,
          ayahNumber: 1,
          timestampFrom: 0,
          timestampTo: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on invalid ayahNumber', () {
      expect(
        () => AyahTiming(
          surahNumber: 1,
          ayahNumber: 0,
          timestampFrom: 0,
          timestampTo: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on negative timestampFrom', () {
      expect(
        () => AyahTiming(
          surahNumber: 1,
          ayahNumber: 1,
          timestampFrom: -5,
          timestampTo: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when timestampTo < timestampFrom', () {
      expect(
        () => AyahTiming(
          surahNumber: 1,
          ayahNumber: 1,
          timestampFrom: 5000,
          timestampTo: 4000,
        ),
        throwsArgumentError,
      );
    });

    test('containsPosition correctly evaluates boundaries', () {
      final timing = AyahTiming(
        surahNumber: 2,
        ayahNumber: 255,
        timestampFrom: 10000,
        timestampTo: 25000,
      );

      expect(timing.containsPosition(9999), isFalse);
      expect(timing.containsPosition(10000), isTrue);
      expect(timing.containsPosition(17500), isTrue);
      expect(timing.containsPosition(24999), isTrue);
      expect(timing.containsPosition(25000), isFalse);
    });
  });
}
