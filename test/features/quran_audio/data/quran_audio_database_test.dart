import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_database.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_reciter_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/ayah_timing_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/playback_position_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/surah_audio_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';

void main() {
  group('QuranAudioDatabase Tests', () {
    late QuranAudioDatabase db;

    setUp(() async {
      // Use in-memory SQLite implementation for pure headless unit testing
      db = QuranAudioDatabase.inMemory();
      await db.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('Reciters CRUD: save and retrieve reciters', () async {
      final reciters = [
        AudioReciterModel(
          id: '7',
          name: 'Mishari Rashid al-Afasy',
          arabicName: 'مشاري راشد العفاسي',
          style: 'Murattal',
          qirat: 'Hafs',
        ),
        AudioReciterModel(
          id: '1',
          name: 'AbdulBaset AbdulSamad',
          arabicName: 'عبد الباسط عبد الصمد',
          style: 'Mujawwad',
          qirat: 'Hafs',
        ),
      ];

      await db.saveReciters(reciters);
      final retrieved = await db.getReciters();

      expect(retrieved.length, 2);
      expect(retrieved[0].id, '7');
      expect(retrieved[0].arabicName, 'مشاري راشد العفاسي');
      expect(retrieved[1].id, '1');
      expect(retrieved[1].style, 'Mujawwad');
    });

    test('Surah Audio & Ayah Timings: cache and retrieve with full timing list', () async {
      final timings = [
        AyahTimingModel(
          surahNumber: 1,
          ayahNumber: 1,
          timestampFrom: 0,
          timestampTo: 5800,
          duration: 5800,
        ),
        AyahTimingModel(
          surahNumber: 1,
          ayahNumber: 2,
          timestampFrom: 5800,
          timestampTo: 11200,
          duration: 5400,
        ),
      ];

      final surahAudio = SurahAudioModel(
        surahNumber: 1,
        reciterId: '7',
        audioUrl: 'https://example.com/audio/1.mp3',
        durationMs: 11200,
        ayahTimings: timings,
      );

      await db.saveSurahAudio(surahAudio);
      final retrieved = await db.getSurahAudio(1, '7');

      expect(retrieved, isNotNull);
      expect(retrieved!.surahNumber, 1);
      expect(retrieved.reciterId, '7');
      expect(retrieved.durationMs, 11200);
      expect(retrieved.ayahTimings.length, 2);
      expect(retrieved.ayahTimings[0].verseKey, '1:1');
      expect(retrieved.ayahTimings[1].timestampTo, 11200);

      // Verify null returned for nonexistent record
      final nonExistent = await db.getSurahAudio(2, '7');
      expect(nonExistent, isNull);
    });

    test('Download Registry: full lifecycle with missing & corrupted statuses', () async {
      final download1 = AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 839808,
      );

      final download2 = AudioDownloadModel(
        surahNumber: 2,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_002.mp3',
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: 500000,
      );

      final downloadOtherReciter = AudioDownloadModel(
        surahNumber: 1,
        reciterId: '1',
        localRelativePath: 'reciter_1/surah_001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 900000,
      );

      await db.saveDownload(download1);
      await db.saveDownload(download2);
      await db.saveDownload(downloadOtherReciter);

      // Query single
      final rec1 = await db.getDownload(1, '7');
      expect(rec1, isNotNull);
      expect(rec1!.status, AudioDownloadStatus.completed);
      expect(rec1.actualSizeBytes, 839808);

      // Query by reciter
      final reciter7List = await db.getDownloads(reciterId: '7');
      expect(reciter7List.length, 2);

      // Query all
      final allList = await db.getDownloads();
      expect(allList.length, 3);

      // Update to missing status
      final missingRecord = download1.copyWith(status: AudioDownloadStatus.missing);
      await db.saveDownload(missingRecord);
      final updated = await db.getDownload(1, '7');
      expect(updated!.status, AudioDownloadStatus.missing);

      // Delete single
      await db.deleteDownload(2, '7');
      expect(await db.getDownload(2, '7'), isNull);

      // Delete by reciter
      await db.deleteReciterDownloads('1');
      expect(await db.getDownloads(reciterId: '1'), isEmpty);
      expect(await db.getDownloads(reciterId: '7'), isNotEmpty);

      // Clear all
      await db.deleteAllDownloads();
      expect(await db.getDownloads(), isEmpty);
    });

    test('Playback Position: save and get latest position', () async {
      expect(await db.getPlaybackPosition(), isNull);

      final pos = PlaybackPositionModel(
        reciterId: '7',
        surahNumber: 18,
        positionMs: 65400,
        currentAyahNumber: 10,
        durationMs: 1200000,
        updatedAt: DateTime(2026, 11, 16, 22, 0),
      );

      await db.savePlaybackPosition(pos);
      final restored = await db.getPlaybackPosition();

      expect(restored, isNotNull);
      expect(restored!.reciterId, '7');
      expect(restored.surahNumber, 18);
      expect(restored.positionMs, 65400);
      expect(restored.currentAyahNumber, 10);
      expect(restored.durationMs, 1200000);
    });
  });
}
