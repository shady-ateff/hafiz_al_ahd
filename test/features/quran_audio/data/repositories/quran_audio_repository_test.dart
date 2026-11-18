import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_reciter_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/playback_position_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/surah_audio_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/repositories/quran_audio_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/playback_position.dart';

class FakeQuranAudioRemoteDataSource implements BaseQuranAudioRemoteDataSource {
  List<AudioReciterModel> recitersToReturn = [];
  SurahAudioModel? surahAudioToReturn;
  bool shouldThrow = false;

  @override
  Future<List<AudioReciterModel>> getChapterReciters() async {
    if (shouldThrow) throw Exception('Network error');
    return recitersToReturn;
  }

  @override
  Future<SurahAudioModel> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    if (shouldThrow) throw Exception('Network error');
    if (surahAudioToReturn != null) return surahAudioToReturn!;
    throw Exception('Not found (404)');
  }

  @override
  Future<int?> getRemoteAudioContentLength(String audioUrl) async => 1000000;
}

class FakeQuranAudioLocalDataSource implements BaseQuranAudioLocalDataSource {
  List<AudioReciterModel>? cachedReciters;
  String? selectedReciterId;
  final Map<String, SurahAudioModel> cachedSurahs = {};
  final Map<String, AudioDownloadModel> downloadRegistry = {};
  PlaybackPositionModel? lastPos;

  @override
  Future<List<AudioReciterModel>?> getCachedReciters() async => cachedReciters;

  @override
  Future<void> cacheReciters(List<AudioReciterModel> reciters) async {
    cachedReciters = reciters;
  }

  @override
  Future<String?> getSelectedReciterId() async => selectedReciterId;

  @override
  Future<void> setSelectedReciterId(String reciterId) async {
    selectedReciterId = reciterId;
  }

  @override
  Future<SurahAudioModel?> getCachedSurahAudio(int surahNumber, String reciterId) async {
    return cachedSurahs['${reciterId}_$surahNumber'];
  }

  @override
  Future<void> cacheSurahAudio(SurahAudioModel audio) async {
    cachedSurahs['${audio.reciterId}_${audio.surahNumber}'] = audio;
  }

  @override
  Future<List<AudioDownloadModel>> getDownloadRecords({String? reciterId}) async {
    final values = downloadRegistry.values.toList();
    if (reciterId != null) return values.where((v) => v.reciterId == reciterId).toList();
    return values;
  }

  @override
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId) async {
    return downloadRegistry['$reciterId:$surahNumber'];
  }

  @override
  Future<void> saveDownloadRecord(AudioDownloadModel record) async {
    downloadRegistry['${record.reciterId}:${record.surahNumber}'] = record;
  }

  @override
  Future<void> removeDownloadRecord(int surahNumber, String reciterId) async {
    downloadRegistry.remove('$reciterId:$surahNumber');
  }

  @override
  Future<void> removeReciterDownloadRecords(String reciterId) async {
    downloadRegistry.removeWhere((k, _) => k.startsWith('$reciterId:'));
  }

  @override
  Future<void> clearAllDownloadRecords() async {
    downloadRegistry.clear();
  }

  @override
  Future<PlaybackPositionModel?> getLastPlaybackPosition() async => lastPos;

  @override
  Future<void> savePlaybackPosition(PlaybackPositionModel position) async {
    lastPos = position;
  }
}

void main() {
  group('QuranAudioRepositoryImpl', () {
    late FakeQuranAudioRemoteDataSource remote;
    late FakeQuranAudioLocalDataSource local;
    late QuranAudioRepositoryImpl repo;

    setUp(() {
      remote = FakeQuranAudioRemoteDataSource();
      local = FakeQuranAudioLocalDataSource();
      repo = QuranAudioRepositoryImpl(remoteDataSource: remote, localDataSource: local);
    });

    test('returns cached reciters first without calling remote', () async {
      local.cachedReciters = [
        AudioReciterModel(id: '7', name: 'Alafasy', arabicName: 'العفاسي')
      ];

      final result = await repo.getReciters();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should be right'), (list) {
        expect(list.length, 1);
        expect(list.first.id, '7');
      });
    });

    test('fetches from remote and updates local cache when cache is empty', () async {
      remote.recitersToReturn = [
        AudioReciterModel(id: '6', name: 'Husary', arabicName: 'الحصري')
      ];

      final result = await repo.getReciters();

      expect(result.isRight(), isTrue);
      expect(local.cachedReciters?.first.id, '6');
    });

    test('returns default fallback reciter if both remote and cache fail', () async {
      remote.shouldThrow = true;

      final result = await repo.getReciters();

      expect(result.isLeft(), isTrue); // Network failure returned
    });

    test('saves and restores playback position', () async {
      final pos = PlaybackPosition(
        reciterId: '7',
        surahNumber: 1,
        positionMs: 5000,
        currentAyahNumber: 2,
      );

      final saveRes = await repo.savePlaybackPosition(pos);
      expect(saveRes.isRight(), isTrue);

      final loadRes = await repo.getLastPlaybackPosition();
      expect(loadRes.isRight(), isTrue);
      loadRes.fold((_) => fail('should be right'), (loaded) {
        expect(loaded?.reciterId, '7');
        expect(loaded?.surahNumber, 1);
        expect(loaded?.positionMs, 5000);
      });
    });
  });
}
