import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_reciter_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/playback_position_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/surah_audio_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/audio_download_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';

class FakeLocalDataSource implements BaseQuranAudioLocalDataSource {
  final Map<String, AudioDownloadModel> registry = {};

  @override
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId) async {
    return registry['$reciterId:$surahNumber'];
  }

  @override
  Future<List<AudioDownloadModel>> getDownloadRecords({String? reciterId}) async {
    final values = registry.values.toList();
    if (reciterId != null) return values.where((v) => v.reciterId == reciterId).toList();
    return values;
  }

  @override
  Future<void> saveDownloadRecord(AudioDownloadModel record) async {
    registry['${record.reciterId}:${record.surahNumber}'] = record;
  }

  @override
  Future<void> removeDownloadRecord(int surahNumber, String reciterId) async {
    registry.remove('$reciterId:$surahNumber');
  }

  @override
  Future<void> removeReciterDownloadRecords(String reciterId) async {
    registry.removeWhere((k, _) => k.startsWith('$reciterId:'));
  }

  @override
  Future<void> clearAllDownloadRecords() async {
    registry.clear();
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

void main() {
  group('AudioDownloadRepositoryImpl', () {
    late Directory tempRoot;
    late QuranAudioStorageService storageService;
    late FakeLocalDataSource localDataSource;
    late AudioDownloadRepositoryImpl repo;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('download_repo_test_');
      storageService = QuranAudioStorageService(
        customBaseDirectoryProvider: () => tempRoot,
      );
      localDataSource = FakeLocalDataSource();
      repo = AudioDownloadRepositoryImpl(
        localDataSource: localDataSource,
        storageService: storageService,
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('isSurahDownloaded returns true only when both DB record and physical file exist', () async {
      // 1. Initial state: not downloaded
      expect(await repo.isSurahDownloaded(surahNumber: 1, reciterId: '7'), isFalse);

      // 2. Add DB record without physical file
      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 1000,
      ));

      // Physical file missing -> self-heals by removing stale record
      expect(await repo.isSurahDownloaded(surahNumber: 1, reciterId: '7'), isFalse);
      expect(await localDataSource.getDownloadRecord(1, '7'), isNull);

      // 3. Add physical file AND DB record
      final file = await storageService.resolveSurahFile(1, '7');
      await file.parent.create(recursive: true);
      await file.writeAsString('audio_content');

      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 1000,
      ));

      expect(await repo.isSurahDownloaded(surahNumber: 1, reciterId: '7'), isTrue);
    });

    test('deleteDownloadRecord deletes physical file and registry entry', () async {
      final file = await storageService.resolveSurahFile(1, '7');
      await file.parent.create(recursive: true);
      await file.writeAsString('audio_bytes');

      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: 1,
        reciterId: '7',
        localRelativePath: 'reciter_7/surah_001.mp3',
        status: AudioDownloadStatus.completed,
        actualSizeBytes: 1000,
      ));

      final result = await repo.deleteDownloadRecord(surahNumber: 1, reciterId: '7');
      expect(result.isRight(), isTrue);
      expect(await file.exists(), isFalse);
      expect(await localDataSource.getDownloadRecord(1, '7'), isNull);
    });

    test('reconcileStorage delegates to storage service and returns summary', () async {
      // Create physical file unindexed in DB
      final file = await storageService.resolveSurahFile(112, '7');
      await file.parent.create(recursive: true);
      await file.writeAsString('surah_112_audio');

      final result = await repo.reconcileStorage();
      expect(result.isRight(), isTrue);

      result.fold((_) => fail('should be right'), (summary) {
        expect(summary.discoveredFiles, 1);
        expect(summary.missingFiles, 0);
      });

      // Verify that surah 112 is now known and playable
      expect(await repo.isSurahDownloaded(surahNumber: 112, reciterId: '7'), isTrue);
    });
  });
}
