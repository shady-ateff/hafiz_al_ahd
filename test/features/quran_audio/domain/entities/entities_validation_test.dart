import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';

void main() {
  group('AudioReciter Entity', () {
    test('creates valid reciter with display name precedence', () {
      final reciter = AudioReciter(
        id: '7',
        name: 'Mishari Rashid al-`Afasy',
        arabicName: 'مشاري راشد العفاسي',
        style: 'Murattal',
      );

      expect(reciter.id, '7');
      expect(reciter.displayName, 'مشاري راشد العفاسي');
    });

    test('falls back to English name when arabicName is empty', () {
      final reciter = AudioReciter(
        id: '99',
        name: 'English Name',
        arabicName: '',
      );

      expect(reciter.displayName, 'English Name');
    });

    test('throws ArgumentError on empty ID or empty names', () {
      expect(
        () => AudioReciter(id: '', name: 'Test', arabicName: ''),
        throwsArgumentError,
      );
      expect(
        () => AudioReciter(id: '1', name: '', arabicName: ''),
        throwsArgumentError,
      );
    });
  });

  group('SurahAudio Entity', () {
    test('creates valid SurahAudio and retrieves Ayah timing', () {
      final timing = AyahTiming(
        surahNumber: 1,
        ayahNumber: 1,
        timestampFrom: 0,
        timestampTo: 5000,
      );
      final audio = SurahAudio(
        surahNumber: 1,
        reciterId: '7',
        audioUrl: 'https://example.com/1.mp3',
        durationMs: 46000,
        ayahTimings: [timing],
      );

      expect(audio.surahNumber, 1);
      expect(audio.hasTimings, isTrue);
      expect(audio.getTimingForAyah(1), timing);
      expect(audio.getTimingForAyah(2), isNull);
    });

    test('throws ArgumentError on invalid parameters', () {
      expect(
        () => SurahAudio(
          surahNumber: 0,
          reciterId: '7',
          audioUrl: 'https://example.com',
          durationMs: 1000,
        ),
        throwsArgumentError,
      );
      expect(
        () => SurahAudio(
          surahNumber: 1,
          reciterId: '',
          audioUrl: 'https://example.com',
          durationMs: 1000,
        ),
        throwsArgumentError,
      );
      expect(
        () => SurahAudio(
          surahNumber: 1,
          reciterId: '7',
          audioUrl: '',
          durationMs: 1000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AudioDownload Entity & Path Security', () {
    test('creates valid download record', () {
      final download = AudioDownload(
        surahNumber: 18,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_018.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 31936670,
      );

      expect(download.isPlayable, isTrue);
    });

    test('strictly rejects path traversal sequences', () {
      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: '../outside/file.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 1000,
        ),
        throwsArgumentError,
      );

      expect(
        () => AudioDownload(
          surahNumber: 1,
          reciterId: '7',
          localRelativePath: '/absolute/path.mp3',
          status: AudioDownloadStatus.completed,
          actualSizeBytes: 1000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PlaybackPosition Entity', () {
    test('converts positionMs to Duration accurately', () {
      final pos = PlaybackPosition(
        reciterId: '7',
        surahNumber: 2,
        positionMs: 65000,
        currentAyahNumber: 10,
        durationMs: 7264000,
      );

      expect(pos.positionDuration, const Duration(milliseconds: 65000));
      expect(pos.totalDuration, const Duration(milliseconds: 7264000));
    });
  });

  group('AudioHighlightState Decoupling', () {
    test('supports independent highlight and repeat state', () {
      const state = AudioHighlightState.idle;
      expect(state.activeAyah, isNull);
      expect(state.isPlaying, isFalse);
      expect(state.repeatMode, AudioRepeatMode.continuous);

      final updated = state.copyWith(
        activeAyah: AyahId(surahNumber: 1, ayahNumber: 2),
        isPlaying: true,
        repeatMode: AudioRepeatMode.singleAyah,
      );

      expect(updated.activeAyah, AyahId(surahNumber: 1, ayahNumber: 2));
      expect(updated.isPlaying, isTrue);
      expect(updated.repeatMode, AudioRepeatMode.singleAyah);
    });
  });
}
