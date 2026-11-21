import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/promotion_journal_entry.dart';
import '../models/audio_download_model.dart';
import '../models/audio_reciter_model.dart';
import '../models/playback_position_model.dart';
import '../models/surah_audio_model.dart';
import 'quran_audio_database.dart';

abstract class BaseQuranAudioLocalDataSource {
  // Reciters
  Future<List<AudioReciterModel>?> getCachedReciters();
  Future<void> cacheReciters(List<AudioReciterModel> reciters);

  // User Settings (SharedPreferences)
  Future<String?> getSelectedReciterId();
  Future<void> setSelectedReciterId(String reciterId);

  // Surah Audio & Timings (SQLite)
  Future<SurahAudioModel?> getCachedSurahAudio(int surahNumber, String reciterId);
  Future<void> cacheSurahAudio(SurahAudioModel audio);

  // Downloads Registry (SQLite)
  Future<List<AudioDownloadModel>> getDownloadRecords({String? reciterId});
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId);
  Future<void> saveDownloadRecord(AudioDownloadModel record);
  Future<void> removeDownloadRecord(int surahNumber, String reciterId);
  Future<void> removeReciterDownloadRecords(String reciterId);
  Future<void> clearAllDownloadRecords();

  // Promotion Journal (SQLite - QA.5 Phase 5.3)
  Future<void> savePromotionJournal(PromotionJournalEntry entry);
  Future<PromotionJournalEntry?> getPromotionJournal(int surahNumber, String reciterId);
  Future<List<PromotionJournalEntry>> getAllPromotionJournals();
  Future<void> updatePromotionJournalState({
    required int surahNumber,
    required String reciterId,
    required PromotionJournalState state,
    String? quarantinePath,
    String? quarantineSha256,
  });
  Future<void> removePromotionJournal(int surahNumber, String reciterId);
  Future<void> finalizePromotion({
    required AudioDownloadModel download,
    required int surahNumber,
    required String reciterId,
  });

  // Playback Position (SQLite)
  Future<PlaybackPositionModel?> getLastPlaybackPosition();
  Future<void> savePlaybackPosition(PlaybackPositionModel position);
}

/// Concrete local data source combining SQLite for structured collections
/// and SharedPreferences exclusively for lightweight preferences.
class QuranAudioLocalDataSourceImpl implements BaseQuranAudioLocalDataSource {
  static const String kSelectedReciterIdKey = 'quran_audio_selected_reciter_id';

  final BaseQuranAudioDatabase database;
  final SharedPreferences prefs;

  QuranAudioLocalDataSourceImpl({
    required this.database,
    required this.prefs,
  });

  // ---------------------------------------------------------------------------
  // Reciters (SQLite)
  // ---------------------------------------------------------------------------

  @override
  Future<List<AudioReciterModel>?> getCachedReciters() async {
    final list = await database.getReciters();
    return list.isNotEmpty ? list : null;
  }

  @override
  Future<void> cacheReciters(List<AudioReciterModel> reciters) async {
    await database.saveReciters(reciters);
  }

  // ---------------------------------------------------------------------------
  // User Preferences (SharedPreferences only)
  // ---------------------------------------------------------------------------

  @override
  Future<String?> getSelectedReciterId() async {
    return prefs.getString(kSelectedReciterIdKey);
  }

  @override
  Future<void> setSelectedReciterId(String reciterId) async {
    await prefs.setString(kSelectedReciterIdKey, reciterId);
  }

  // ---------------------------------------------------------------------------
  // Surah Audio & Timings (SQLite)
  // ---------------------------------------------------------------------------

  @override
  Future<SurahAudioModel?> getCachedSurahAudio(int surahNumber, String reciterId) async {
    return database.getSurahAudio(surahNumber, reciterId);
  }

  @override
  Future<void> cacheSurahAudio(SurahAudioModel audio) async {
    await database.saveSurahAudio(audio);
  }

  // ---------------------------------------------------------------------------
  // Downloads Registry (SQLite)
  // ---------------------------------------------------------------------------

  @override
  Future<List<AudioDownloadModel>> getDownloadRecords({String? reciterId}) async {
    return database.getDownloads(reciterId: reciterId);
  }

  @override
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId) async {
    return database.getDownload(surahNumber, reciterId);
  }

  @override
  Future<void> saveDownloadRecord(AudioDownloadModel record) async {
    await database.saveDownload(record);
  }

  @override
  Future<void> removeDownloadRecord(int surahNumber, String reciterId) async {
    await database.deleteDownload(surahNumber, reciterId);
  }

  @override
  Future<void> removeReciterDownloadRecords(String reciterId) async {
    await database.deleteReciterDownloads(reciterId);
  }

  @override
  Future<void> clearAllDownloadRecords() async {
    await database.deleteAllDownloads();
  }

  // ---------------------------------------------------------------------------
  // Promotion Journal (SQLite - QA.5 Phase 5.3)
  // ---------------------------------------------------------------------------

  @override
  Future<void> savePromotionJournal(PromotionJournalEntry entry) async {
    await database.saveJournalEntry(entry);
  }

  @override
  Future<PromotionJournalEntry?> getPromotionJournal(int surahNumber, String reciterId) async {
    return database.getJournalEntry(surahNumber, reciterId);
  }

  @override
  Future<List<PromotionJournalEntry>> getAllPromotionJournals() async {
    return database.getAllJournalEntries();
  }

  @override
  Future<void> updatePromotionJournalState({
    required int surahNumber,
    required String reciterId,
    required PromotionJournalState state,
    String? quarantinePath,
    String? quarantineSha256,
  }) async {
    await database.updateJournalState(
      surahNumber: surahNumber,
      reciterId: reciterId,
      state: state,
      quarantinePath: quarantinePath,
      quarantineSha256: quarantineSha256,
    );
  }

  @override
  Future<void> removePromotionJournal(int surahNumber, String reciterId) async {
    await database.deleteJournalEntry(surahNumber, reciterId);
  }

  @override
  Future<void> finalizePromotion({
    required AudioDownloadModel download,
    required int surahNumber,
    required String reciterId,
  }) async {
    await database.finalizePromotion(
      download: download,
      surahNumber: surahNumber,
      reciterId: reciterId,
    );
  }

  // ---------------------------------------------------------------------------
  // Playback Position (SQLite)
  // ---------------------------------------------------------------------------

  @override
  Future<PlaybackPositionModel?> getLastPlaybackPosition() async {
    return database.getPlaybackPosition();
  }

  @override
  Future<void> savePlaybackPosition(PlaybackPositionModel position) async {
    await database.savePlaybackPosition(position);
  }
}
