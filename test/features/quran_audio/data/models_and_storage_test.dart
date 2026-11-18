import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_reciter_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/playback_position_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/surah_audio_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';

void main() {
  group('Data Models Parsing', () {
    test('AudioReciterModel parses Quran Foundation chapter reciter JSON', () {
      final json = {
        'id': 7,
        'name': 'Mishari Rashid al-`Afasy',
        'style': {'name': 'Murattal', 'language_name': 'english'},
        'qirat': {'name': 'Hafs', 'language_name': 'english'},
        'translated_name': {'name': 'مشاري راشد العفاسي', 'language_name': 'arabic'}
      };

      final model = AudioReciterModel.fromJson(json);

      expect(model.id, '7');
      expect(model.name, 'Mishari Rashid al-`Afasy');
      expect(model.arabicName, 'مشاري راشد العفاسي');
      expect(model.style, 'Murattal');
      expect(model.qirat, 'Hafs');
    });

    test('SurahAudioModel parses Quran Foundation chapter audio JSON', () {
      final json = {
        'id': 911,
        'chapter_id': 1,
        'file_size': 839808.0,
        'format': 'mp3',
        'audio_url': 'https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3',
        'duration': 46000,
        'verse_timings': [
          {
            'verse_key': '1:1',
            'timestamp_from': 0,
            'timestamp_to': 6090,
            'duration': 6090,
            'segments': [[1, 0, 580], [2, 580, 1409]]
          },
          {
            'verse_key': '1:2',
            'timestamp_from': 6090,
            'timestamp_to': 11680,
            'duration': 5590,
          }
        ]
      };

      final model = SurahAudioModel.fromJson(json, fallbackReciterId: '7');

      expect(model.surahNumber, 1);
      expect(model.reciterId, '7');
      expect(model.audioUrl, 'https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3');
      expect(model.durationMs, 46000);
      expect(model.ayahTimings.length, 2);
      expect(model.ayahTimings[0].verseKey, '1:1');
      expect(model.ayahTimings[0].timestampTo, 6090);
      expect(model.ayahTimings[1].verseKey, '1:2');
    });

    test('AudioDownloadModel serializes and deserializes cleanly', () {
      final model = AudioDownloadModel(
        surahNumber: 36,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_036.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 16902690,
        sha256: 'abc123hash',
      );

      final json = model.toJson();
      final restored = AudioDownloadModel.fromJson(json);

      expect(restored.surahNumber, 36);
      expect(restored.reciterId, '7');
      expect(restored.localRelativePath, 'reciter_7/surah_036.mp3');
      expect(restored.status, AudioDownloadStatus.completed);
      expect(restored.actualSizeBytes, 16902690);
      expect(restored.sha256, 'abc123hash');
    });

    test('PlaybackPositionModel serializes and deserializes cleanly', () {
      final model = PlaybackPositionModel(
        reciterId: '7',
        surahNumber: 2,
        positionMs: 120000,
        currentAyahNumber: 15,
        durationMs: 7264000,
      );

      final json = model.toJson();
      final restored = PlaybackPositionModel.fromJson(json);

      expect(restored.reciterId, '7');
      expect(restored.surahNumber, 2);
      expect(restored.positionMs, 120000);
      expect(restored.currentAyahNumber, 15);
      expect(restored.durationMs, 7264000);
    });
  });

  group('QuranAudioStorageService Isolation & Safety', () {
    late Directory tempRoot;
    late QuranAudioStorageService storageService;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('quran_audio_test_');
      storageService = QuranAudioStorageService(
        customBaseDirectoryProvider: () => tempRoot,
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('builds standard relative path with padding and sanitizes traversal chars', () {
      final rel = QuranAudioStorageService.buildRelativePath(1, '7');
      expect(rel, 'reciter_7/surah_001.mp3');

      final rel2 = QuranAudioStorageService.buildRelativePath(114, 'ar.alafasy');
      expect(rel2, 'reciter_ar_alafasy/surah_114.mp3');

      // Traversal sanitization
      final relMalicious = QuranAudioStorageService.buildRelativePath(1, '../../etc/passwd');
      expect(relMalicious.contains('..'), isFalse);
      expect(relMalicious.startsWith('reciter_'), isTrue);
    });

    test('promotes staging file atomically and creates directory structure', () async {
      final staging = await storageService.createStagingFile('token123', 1, '7');
      await staging.parent.create(recursive: true);
      await staging.writeAsString('simulated_audio_payload');

      expect(await staging.exists(), isTrue);

      final promoted = await storageService.promoteStagingFile(
        stagingFile: staging,
        surahNumber: 1,
        reciterId: '7',
      );

      expect(await staging.exists(), isFalse); // Staging renamed
      expect(await promoted.exists(), isTrue);
      expect(promoted.path.replaceAll('\\', '/').endsWith('reciter_7/surah_001.mp3'), isTrue);
      expect(await promoted.readAsString(), 'simulated_audio_payload');
    });

    test('promotes staging file safely when destination file already exists and is valid', () async {
      final dest = await storageService.resolveSurahFile(1, '7');
      await dest.parent.create(recursive: true);
      await dest.writeAsString('existing_valid_file');

      final staging = await storageService.createStagingFile('token456', 1, '7');
      await staging.writeAsString('new_staging_file');

      final result = await storageService.promoteStagingFile(
        stagingFile: staging,
        surahNumber: 1,
        reciterId: '7',
        expectedSizeBytes: 'existing_valid_file'.length,
      );

      expect(result.path, dest.path);
      // Valid target preserved, staging removed
      expect(await dest.readAsString(), 'existing_valid_file');
      expect(await staging.exists(), isFalse);
    });

    test('promotes staging file overwriting corrupt existing destination', () async {
      final dest = await storageService.resolveSurahFile(1, '7');
      await dest.parent.create(recursive: true);
      await dest.writeAsString(''); // 0 bytes = corrupt

      final staging = await storageService.createStagingFile('token789', 1, '7');
      await staging.writeAsString('fresh_clean_audio');

      final result = await storageService.promoteStagingFile(
        stagingFile: staging,
        surahNumber: 1,
        reciterId: '7',
        expectedSizeBytes: 'fresh_clean_audio'.length,
      );

      expect(result.path, dest.path);
      expect(await dest.readAsString(), 'fresh_clean_audio');
      expect(await staging.exists(), isFalse);
    });

    test('deletes individual Surah file and reciter directory safely', () async {
      final file = await storageService.resolveSurahFile(1, '7');
      await file.parent.create(recursive: true);
      await file.writeAsString('audio');

      expect(await file.exists(), isTrue);

      final deleted = await storageService.deleteSurahFile(1, '7');
      expect(deleted, isTrue);
      expect(await file.exists(), isFalse);

      // Recreate and delete whole reciter
      await file.writeAsString('audio');
      final count = await storageService.deleteReciterDirectory('7');
      expect(count, 1);
      expect(await file.parent.exists(), isFalse);
    });

    test('storage reconciliation: discovers unindexed files, flags missing files, cleans stale tmp', () async {
      final fakeLocalDataSource = _FakeLocalDataSourceForStorage();

      // 1. Create a physical Surah file not present in localDataSource registry (simulating crash before DB insert)
      final unindexedFile = await storageService.resolveSurahFile(1, '7');
      await unindexedFile.parent.create(recursive: true);
      await unindexedFile.writeAsString('surah_1_audio_bytes');

      // 2. Put a record in registry whose physical file DOES NOT exist on disk
      await fakeLocalDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 2,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_002.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 5000,
      ));

      // 3. Create a stale staging temp file (> 2 hours old) and a fresh staging file
      final stagingDir = await storageService.getStagingDirectory();
      final staleTemp = File('${stagingDir.path}/dl_old_reciter_7_003.tmp');
      await staleTemp.writeAsString('abandoned');
      // Set modified time in the past
      await staleTemp.setLastModified(DateTime.now().subtract(const Duration(hours: 3)));

      final freshTemp = File('${stagingDir.path}/dl_fresh_reciter_7_004.tmp');
      await freshTemp.writeAsString('active_download');

      // Run reconciliation
      final summary = await storageService.reconcileStorageWithRegistry(
        fakeLocalDataSource,
        abandonedStagingThreshold: const Duration(hours: 1),
      );

      expect(summary.discoveredFiles, 1);
      expect(summary.missingFiles, 1);
      expect(summary.cleanedTempFiles, 1);

      // Check that unindexed physical file was registered
      final registeredSurah1 = await fakeLocalDataSource.getDownloadRecord(1, '7');
      expect(registeredSurah1, isNotNull);
      expect(registeredSurah1!.status, AudioDownloadStatus.completed);
      expect(registeredSurah1.actualSizeBytes, 'surah_1_audio_bytes'.length);

      // Check that missing file was updated to missing status
      final updatedSurah2 = await fakeLocalDataSource.getDownloadRecord(2, '7');
      expect(updatedSurah2, isNotNull);
      expect(updatedSurah2!.status, AudioDownloadStatus.missing);

      // Check that stale temp was deleted and fresh temp remains
      expect(await staleTemp.exists(), isFalse);
      expect(await freshTemp.exists(), isTrue);
    });
  });
}

class _FakeLocalDataSourceForStorage implements BaseQuranAudioLocalDataSource {
  final Map<String, AudioDownloadModel> records = {};

  @override
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId) async {
    return records['$reciterId:$surahNumber'];
  }

  @override
  Future<List<AudioDownloadModel>> getDownloadRecords({String? reciterId}) async {
    final list = records.values.toList();
    if (reciterId != null) return list.where((r) => r.reciterId == reciterId).toList();
    return list;
  }

  @override
  Future<void> saveDownloadRecord(AudioDownloadModel record) async {
    records['${record.reciterId}:${record.surahNumber}'] = record;
  }

  @override
  Future<void> removeDownloadRecord(int surahNumber, String reciterId) async {
    records.remove('$reciterId:$surahNumber');
  }

  @override
  Future<void> removeReciterDownloadRecords(String reciterId) async {
    records.removeWhere((k, _) => k.startsWith('$reciterId:'));
  }

  @override
  Future<void> clearAllDownloadRecords() async {
    records.clear();
  }

  @override
  Future<List<AudioReciterModel>?> getCachedReciters() async => null;
  @override
  Future<void> cacheReciters(List<AudioReciterModel> reciters) async {}
  @override
  Future<String?> getSelectedReciterId() async => null;
  @override
  Future<void> setSelectedReciterId(String reciterId) async {}
  @override
  Future<SurahAudioModel?> getCachedSurahAudio(int surahNumber, String reciterId) async => null;
  @override
  Future<void> cacheSurahAudio(SurahAudioModel audio) async {}
  @override
  Future<PlaybackPositionModel?> getLastPlaybackPosition() async => null;
  @override
  Future<void> savePlaybackPosition(PlaybackPositionModel position) async {}
}
