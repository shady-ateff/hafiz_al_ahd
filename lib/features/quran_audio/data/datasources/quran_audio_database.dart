import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/audio_download_model.dart';
import '../models/audio_reciter_model.dart';
import '../models/ayah_timing_model.dart';
import '../models/playback_position_model.dart';
import '../models/surah_audio_model.dart';

/// Database contract for the Quran Audio subsystem.
abstract class BaseQuranAudioDatabase {
  Future<void> init();

  // Reciters
  Future<List<AudioReciterModel>> getReciters();
  Future<void> saveReciters(List<AudioReciterModel> reciters);

  // Surah Audio Tracks & Timings
  Future<SurahAudioModel?> getSurahAudio(int surahNumber, String reciterId);
  Future<void> saveSurahAudio(SurahAudioModel audio);
  Future<List<AyahTimingModel>> getAyahTimings(int surahNumber, String reciterId);

  // Downloads Registry
  Future<List<AudioDownloadModel>> getDownloads({String? reciterId});
  Future<AudioDownloadModel?> getDownload(int surahNumber, String reciterId);
  Future<void> saveDownload(AudioDownloadModel download);
  Future<void> deleteDownload(int surahNumber, String reciterId);
  Future<void> deleteReciterDownloads(String reciterId);
  Future<void> deleteAllDownloads();

  // Playback Positions
  Future<PlaybackPositionModel?> getPlaybackPosition({
    String? reciterId,
    int? surahNumber,
  });
  Future<void> savePlaybackPosition(PlaybackPositionModel position);

  Future<void> close();
}

/// SQLite-backed implementation of [BaseQuranAudioDatabase] using `sqflite`.
///
/// **ARCHITECTURAL ISOLATION**:
/// Stored in a separate database file (`quran_audio.db`) completely independent
/// from the existing Quran text database (`quran_v7.db`).
class QuranAudioDatabase implements BaseQuranAudioDatabase {
  static const String kDatabaseName = 'quran_audio.db';
  static const int kDatabaseVersion = 1;

  Database? _db;
  final String? customDatabasePath;

  // In-memory fallback store used in unit tests or desktop platforms where sqflite native driver is absent
  final Map<String, AudioReciterModel> _memReciters = {};
  final Map<String, SurahAudioModel> _memTracks = {};
  final Map<String, List<AyahTimingModel>> _memTimings = {};
  final Map<String, AudioDownloadModel> _memDownloads = {};
  final Map<String, PlaybackPositionModel> _memPositions = {};
  bool _useInMemoryFallback = false;

  QuranAudioDatabase({this.customDatabasePath});

  QuranAudioDatabase.inMemory() : customDatabasePath = null {
    _useInMemoryFallback = true;
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Future<void> init() async {
    if (_db != null || _useInMemoryFallback) return;

    if (_isDesktop && customDatabasePath == null) {
      // Desktop without custom sqflite driver -> use in-memory fallback
      _useInMemoryFallback = true;
      return;
    }

    try {
      final dbPath = customDatabasePath ??
          p.join(await getDatabasesPath(), kDatabaseName);

      _db = await openDatabase(
        dbPath,
        version: kDatabaseVersion,
        onCreate: _onCreate,
      );
    } catch (e) {
      debugPrint('[QuranAudioDatabase] SQLite init failed, falling back to memory store: $e');
      _useInMemoryFallback = true;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_reciters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        arabic_name TEXT NOT NULL,
        style TEXT,
        qirat TEXT,
        description TEXT,
        provider TEXT NOT NULL,
        available_format TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_surah_tracks (
        surah_number INTEGER NOT NULL,
        reciter_id TEXT NOT NULL,
        audio_url TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        format TEXT NOT NULL,
        expected_content_length INTEGER,
        PRIMARY KEY (reciter_id, surah_number)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_ayah_timings (
        surah_number INTEGER NOT NULL,
        reciter_id TEXT NOT NULL,
        ayah_number INTEGER NOT NULL,
        timestamp_from INTEGER NOT NULL,
        timestamp_to INTEGER NOT NULL,
        duration INTEGER NOT NULL,
        PRIMARY KEY (reciter_id, surah_number, ayah_number)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ayah_timings 
      ON quran_audio_ayah_timings (reciter_id, surah_number);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_downloads (
        surah_number INTEGER NOT NULL,
        reciter_id TEXT NOT NULL,
        local_relative_path TEXT NOT NULL,
        status TEXT NOT NULL,
        actual_size_bytes INTEGER NOT NULL,
        sha256 TEXT,
        downloaded_at TEXT NOT NULL,
        PRIMARY KEY (reciter_id, surah_number)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_playback_positions (
        reciter_id TEXT NOT NULL,
        surah_number INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        current_ayah_number INTEGER NOT NULL,
        duration_ms INTEGER,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (reciter_id, surah_number)
      );
    ''');
  }

  // ---------------------------------------------------------------------------
  // Reciters
  // ---------------------------------------------------------------------------

  @override
  Future<List<AudioReciterModel>> getReciters() async {
    await init();
    if (_useInMemoryFallback) {
      return _memReciters.values.toList();
    }

    final maps = await _db!.query('quran_audio_reciters');
    return maps.map((m) => AudioReciterModel.fromJson(m)).toList();
  }

  @override
  Future<void> saveReciters(List<AudioReciterModel> reciters) async {
    await init();
    if (_useInMemoryFallback) {
      for (final r in reciters) {
        _memReciters[r.id] = r;
      }
      return;
    }

    final batch = _db!.batch();
    for (final r in reciters) {
      batch.insert(
        'quran_audio_reciters',
        r.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------------
  // Surah Audio Tracks & Timings
  // ---------------------------------------------------------------------------

  @override
  Future<SurahAudioModel?> getSurahAudio(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      return _memTracks['${reciterId}_$surahNumber'];
    }

    final tracks = await _db!.query(
      'quran_audio_surah_tracks',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
      limit: 1,
    );

    if (tracks.isEmpty) return null;

    final timings = await getAyahTimings(surahNumber, reciterId);
    final map = Map<String, dynamic>.from(tracks.first);
    map['ayah_timings'] = timings.map((t) => t.toJson()).toList();

    return SurahAudioModel.fromJson(map);
  }

  @override
  Future<void> saveSurahAudio(SurahAudioModel audio) async {
    await init();
    if (_useInMemoryFallback) {
      _memTracks['${audio.reciterId}_${audio.surahNumber}'] = audio;
      final timings = audio.ayahTimings
          .map((t) => t is AyahTimingModel ? t : AyahTimingModel.fromEntity(t))
          .toList();
      _memTimings['${audio.reciterId}_${audio.surahNumber}'] = timings;
      return;
    }

    await _db!.transaction((txn) async {
      await txn.insert(
        'quran_audio_surah_tracks',
        {
          'surah_number': audio.surahNumber,
          'reciter_id': audio.reciterId,
          'audio_url': audio.audioUrl,
          'duration_ms': audio.durationMs,
          'format': audio.format,
          'expected_content_length': audio.expectedContentLength,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert timing segments
      final batch = txn.batch();
      // Remove old timings first
      batch.delete(
        'quran_audio_ayah_timings',
        where: 'surah_number = ? AND reciter_id = ?',
        whereArgs: [audio.surahNumber, audio.reciterId],
      );

      for (final t in audio.ayahTimings) {
        batch.insert(
          'quran_audio_ayah_timings',
          {
            'surah_number': t.surahNumber,
            'reciter_id': audio.reciterId,
            'ayah_number': t.ayahNumber,
            'timestamp_from': t.timestampFrom,
            'timestamp_to': t.timestampTo,
            'duration': t.duration,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<AyahTimingModel>> getAyahTimings(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      return _memTimings['${reciterId}_$surahNumber'] ?? const [];
    }

    final maps = await _db!.query(
      'quran_audio_ayah_timings',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
      orderBy: 'timestamp_from ASC',
    );

    return maps.map((m) => AyahTimingModel.fromJson(m)).toList();
  }

  // ---------------------------------------------------------------------------
  // Downloads Registry
  // ---------------------------------------------------------------------------

  @override
  Future<List<AudioDownloadModel>> getDownloads({String? reciterId}) async {
    await init();
    if (_useInMemoryFallback) {
      final list = _memDownloads.values.toList();
      if (reciterId != null) return list.where((d) => d.reciterId == reciterId).toList();
      return list;
    }

    final maps = reciterId != null
        ? await _db!.query('quran_audio_downloads', where: 'reciter_id = ?', whereArgs: [reciterId])
        : await _db!.query('quran_audio_downloads');

    return maps.map((m) => AudioDownloadModel.fromJson(m)).toList();
  }

  @override
  Future<AudioDownloadModel?> getDownload(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      return _memDownloads['$reciterId:$surahNumber'];
    }

    final maps = await _db!.query(
      'quran_audio_downloads',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return AudioDownloadModel.fromJson(maps.first);
  }

  @override
  Future<void> saveDownload(AudioDownloadModel download) async {
    await init();
    if (_useInMemoryFallback) {
      _memDownloads['${download.reciterId}:${download.surahNumber}'] = download;
      return;
    }

    await _db!.insert(
      'quran_audio_downloads',
      download.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteDownload(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      _memDownloads.remove('$reciterId:$surahNumber');
      return;
    }

    await _db!.delete(
      'quran_audio_downloads',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
    );
  }

  @override
  Future<void> deleteReciterDownloads(String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      _memDownloads.removeWhere((k, _) => k.startsWith('$reciterId:'));
      return;
    }

    await _db!.delete(
      'quran_audio_downloads',
      where: 'reciter_id = ?',
      whereArgs: [reciterId],
    );
  }

  @override
  Future<void> deleteAllDownloads() async {
    await init();
    if (_useInMemoryFallback) {
      _memDownloads.clear();
      return;
    }

    await _db!.delete('quran_audio_downloads');
  }

  // ---------------------------------------------------------------------------
  // Playback Positions
  // ---------------------------------------------------------------------------

  @override
  Future<PlaybackPositionModel?> getPlaybackPosition({
    String? reciterId,
    int? surahNumber,
  }) async {
    await init();
    if (_useInMemoryFallback) {
      if (reciterId != null && surahNumber != null) {
        return _memPositions['${reciterId}_$surahNumber'];
      }
      if (_memPositions.isNotEmpty) {
        // Return most recently updated
        final sorted = _memPositions.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return sorted.first;
      }
      return null;
    }

    final List<Map<String, dynamic>> maps;
    if (reciterId != null && surahNumber != null) {
      maps = await _db!.query(
        'quran_audio_playback_positions',
        where: 'reciter_id = ? AND surah_number = ?',
        whereArgs: [reciterId, surahNumber],
        limit: 1,
      );
    } else {
      maps = await _db!.query(
        'quran_audio_playback_positions',
        orderBy: 'updated_at DESC',
        limit: 1,
      );
    }

    if (maps.isEmpty) return null;
    return PlaybackPositionModel.fromJson(maps.first);
  }

  @override
  Future<void> savePlaybackPosition(PlaybackPositionModel position) async {
    await init();
    if (_useInMemoryFallback) {
      _memPositions['${position.reciterId}_${position.surahNumber}'] = position;
      return;
    }

    await _db!.insert(
      'quran_audio_playback_positions',
      position.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
