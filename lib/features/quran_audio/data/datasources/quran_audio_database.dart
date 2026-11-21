import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/promotion_journal_entry.dart';
import '../../domain/entities/quran_download_queue.dart';
import '../../domain/entities/quran_download_queue_item.dart';
import '../../domain/entities/quran_download_queue_status.dart';
import '../models/audio_download_model.dart';
import '../models/audio_reciter_model.dart';
import '../models/ayah_timing_model.dart';
import '../models/playback_position_model.dart';
import '../models/promotion_journal_model.dart';
import '../models/quran_download_queue_item_model.dart';
import '../models/quran_download_queue_model.dart';
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

  // Promotion Journal (QA.5 Phase 5.3)
  Future<void> saveJournalEntry(PromotionJournalEntry entry);
  Future<PromotionJournalEntry?> getJournalEntry(int surahNumber, String reciterId);
  Future<List<PromotionJournalEntry>> getAllJournalEntries();
  Future<void> updateJournalState({
    required int surahNumber,
    required String reciterId,
    required PromotionJournalState state,
    String? quarantinePath,
    String? quarantineSha256,
  });
  Future<void> deleteJournalEntry(int surahNumber, String reciterId);
  Future<void> finalizePromotion({
    required AudioDownloadModel download,
    required int surahNumber,
    required String reciterId,
  });

  // Playback Positions
  Future<PlaybackPositionModel?> getPlaybackPosition({
    String? reciterId,
    int? surahNumber,
  });
  Future<void> savePlaybackPosition(PlaybackPositionModel position);

  // Full-Quran Download Queue (QA.6 Phase 6.3)
  Future<void> createQueue({
    required QuranDownloadQueueModel queue,
    required List<QuranDownloadQueueItemModel> items,
  });
  Future<QuranDownloadQueueModel?> getActiveQueue();
  Future<QuranDownloadQueueModel?> getQueueById(String queueId);
  Future<QuranDownloadQueueModel?> getLatestQueueForReciter(String reciterId);
  Future<List<QuranDownloadQueueItemModel>> getQueueItems(String queueId);
  Future<void> updateQueueStatus({
    required String queueId,
    required QuranDownloadQueueStatus status,
    DateTime? completedAt,
  });
  Future<void> updateQueueProgress({
    required String queueId,
    required int completedItems,
    required int downloadedBytes,
    int? totalExpectedBytes,
  });
  Future<void> updateQueueItemStatus({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueItemStatus status,
    int? downloadedBytes,
    String? lastError,
  });
  Future<void> updateQueueAndItemStatusAtomic({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueStatus queueStatus,
    required QuranDownloadQueueItemStatus itemStatus,
    int? downloadedBytes,
    String? lastError,
  });
  Future<void> retryFailedQueueItems(String queueId);
  Future<void> deleteQueue(String queueId);

  Future<void> close();
}

/// SQLite-backed implementation of [BaseQuranAudioDatabase] using `sqflite`.
///
/// **ARCHITECTURAL ISOLATION**:
/// Stored in a separate database file (`quran_audio.db`) completely independent
/// from the existing Quran text database (`quran_v7.db`).
class QuranAudioDatabase implements BaseQuranAudioDatabase {
  static const String kDatabaseName = 'quran_audio.db';
  static const int kDatabaseVersion = 3;

  Database? _db;
  final String? customDatabasePath;

  // In-memory fallback stores used in unit tests or desktop platforms
  final Map<String, AudioReciterModel> _memReciters = {};
  final Map<String, SurahAudioModel> _memTracks = {};
  final Map<String, List<AyahTimingModel>> _memTimings = {};
  final Map<String, AudioDownloadModel> _memDownloads = {};
  final Map<String, PromotionJournalEntry> _memJournals = {};
  final Map<String, PlaybackPositionModel> _memPositions = {};
  final Map<String, QuranDownloadQueue> _memQueues = {};
  final Map<String, List<QuranDownloadQueueItem>> _memQueueItems = {};
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
      _useInMemoryFallback = true;
      return;
    }

    try {
      final dbPath = customDatabasePath ??
          p.join(await getDatabasesPath(), kDatabaseName);

      _db = await openDatabase(
        dbPath,
        version: kDatabaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      debugPrint('[QuranAudioDatabase] SQLite init failed, falling back to memory store: $e');
      _useInMemoryFallback = true;
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
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
        temp_relative_path TEXT,
        status TEXT NOT NULL,
        actual_size_bytes INTEGER NOT NULL,
        expected_size_bytes INTEGER,
        sha256 TEXT,
        transfer_integrity_verified INTEGER NOT NULL DEFAULT 0,
        etag TEXT,
        last_modified TEXT,
        last_error TEXT,
        downloaded_at TEXT NOT NULL,
        completed_at TEXT,
        PRIMARY KEY (reciter_id, surah_number)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_audio_promotion_journal (
        surah_number INTEGER NOT NULL,
        reciter_id TEXT NOT NULL,
        staging_path TEXT NOT NULL,
        staging_sha256 TEXT NOT NULL,
        destination_path TEXT NOT NULL,
        backup_path TEXT,
        previous_sha256 TEXT,
        quarantine_path TEXT,
        quarantine_sha256 TEXT,
        promotion_state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_download_queues (
        id TEXT PRIMARY KEY,
        reciter_id TEXT NOT NULL,
        status TEXT NOT NULL,
        total_items INTEGER NOT NULL DEFAULT 114,
        completed_items INTEGER NOT NULL DEFAULT 0,
        total_expected_bytes INTEGER,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quran_download_queue_items (
        id TEXT PRIMARY KEY,
        queue_id TEXT NOT NULL,
        surah_number INTEGER NOT NULL,
        position INTEGER NOT NULL,
        status TEXT NOT NULL,
        expected_bytes INTEGER,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (queue_id) REFERENCES quran_download_queues (id) ON DELETE CASCADE,
        UNIQUE(queue_id, surah_number),
        UNIQUE(queue_id, position)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_queue_items_queue_pos
      ON quran_download_queue_items (queue_id, position);
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_single_active_queue
      ON quran_download_queues ((CASE WHEN status IN ('pending', 'running', 'paused') THEN 1 ELSE NULL END));
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 1. Add v2 columns to quran_audio_downloads
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN expected_size_bytes INTEGER;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN transfer_integrity_verified INTEGER NOT NULL DEFAULT 0;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN etag TEXT;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN last_modified TEXT;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN last_error TEXT;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN temp_relative_path TEXT;');
      await db.execute('ALTER TABLE quran_audio_downloads ADD COLUMN completed_at TEXT;');

      // 2. Backfill completed_at from downloaded_at for legacy v1 completed downloads
      await db.execute('''
        UPDATE quran_audio_downloads 
        SET completed_at = downloaded_at 
        WHERE status = 'completed';
      ''');

      // 3. Create persistent promotion journal table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS quran_audio_promotion_journal (
          surah_number INTEGER NOT NULL,
          reciter_id TEXT NOT NULL,
          staging_path TEXT NOT NULL,
          staging_sha256 TEXT NOT NULL,
          destination_path TEXT NOT NULL,
          backup_path TEXT,
          previous_sha256 TEXT,
          quarantine_path TEXT,
          quarantine_sha256 TEXT,
          promotion_state TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (reciter_id, surah_number)
        );
      ''');
    }

    if (oldVersion < 3) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quran_download_queues (
            id TEXT PRIMARY KEY,
            reciter_id TEXT NOT NULL,
            status TEXT NOT NULL,
            total_items INTEGER NOT NULL DEFAULT 114,
            completed_items INTEGER NOT NULL DEFAULT 0,
            total_expected_bytes INTEGER,
            downloaded_bytes INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT
          );
        ''');

        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quran_download_queue_items (
            id TEXT PRIMARY KEY,
            queue_id TEXT NOT NULL,
            surah_number INTEGER NOT NULL,
            position INTEGER NOT NULL,
            status TEXT NOT NULL,
            expected_bytes INTEGER,
            downloaded_bytes INTEGER NOT NULL DEFAULT 0,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (queue_id) REFERENCES quran_download_queues (id) ON DELETE CASCADE,
            UNIQUE(queue_id, surah_number),
            UNIQUE(queue_id, position)
          );
        ''');

        await txn.execute('''
          CREATE INDEX IF NOT EXISTS idx_queue_items_queue_pos
          ON quran_download_queue_items (queue_id, position);
        ''');

        // Pre-Index Legacy Sanitization with deterministic tie-breaker
        final activeQueues = await txn.rawQuery('''
          SELECT id FROM quran_download_queues
          WHERE status IN ('pending', 'running', 'paused')
          ORDER BY updated_at DESC, created_at DESC, id DESC;
        ''');

        if (activeQueues.isNotEmpty) {
          final survivingId = activeQueues.first['id'] as String;
          final nowIso = DateTime.now().toIso8601String();
          await txn.rawUpdate('''
            UPDATE quran_download_queues
            SET status = 'paused', updated_at = ?
            WHERE id = ?;
          ''', [nowIso, survivingId]);

          for (int i = 1; i < activeQueues.length; i++) {
            final demotedId = activeQueues[i]['id'] as String;
            await txn.rawUpdate('''
              UPDATE quran_download_queues
              SET status = 'cancelled', updated_at = ?
              WHERE id = ?;
            ''', [nowIso, demotedId]);
          }
        }

        await txn.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_single_active_queue
          ON quran_download_queues ((CASE WHEN status IN ('pending', 'running', 'paused') THEN 1 ELSE NULL END));
        ''');
      });
    }
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

      final batch = txn.batch();
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
  // Promotion Journal (QA.5 Phase 5.3)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveJournalEntry(PromotionJournalEntry entry) async {
    await init();
    if (_useInMemoryFallback) {
      _memJournals['${entry.reciterId}:${entry.surahNumber}'] = entry;
      return;
    }

    final model = entry is PromotionJournalModel
        ? entry
        : PromotionJournalModel.fromEntity(entry);

    await _db!.insert(
      'quran_audio_promotion_journal',
      model.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<PromotionJournalEntry?> getJournalEntry(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      return _memJournals['$reciterId:$surahNumber'];
    }

    final maps = await _db!.query(
      'quran_audio_promotion_journal',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return PromotionJournalModel.fromJson(maps.first);
  }

  @override
  Future<List<PromotionJournalEntry>> getAllJournalEntries() async {
    await init();
    if (_useInMemoryFallback) {
      return _memJournals.values.toList();
    }

    final maps = await _db!.query('quran_audio_promotion_journal');
    return maps.map((m) => PromotionJournalModel.fromJson(m)).toList();
  }

  @override
  Future<void> updateJournalState({
    required int surahNumber,
    required String reciterId,
    required PromotionJournalState state,
    String? quarantinePath,
    String? quarantineSha256,
  }) async {
    await init();
    if (_useInMemoryFallback) {
      final existing = _memJournals['$reciterId:$surahNumber'];
      if (existing != null) {
        _memJournals['$reciterId:$surahNumber'] = existing.copyWith(
          promotionState: state,
          quarantinePath: quarantinePath ?? existing.quarantinePath,
          quarantineSha256: quarantineSha256 ?? existing.quarantineSha256,
        );
      }
      return;
    }

    final Map<String, dynamic> updates = {
      'promotion_state': state.dbValue,
    };
    if (quarantinePath != null) updates['quarantine_path'] = quarantinePath;
    if (quarantineSha256 != null) updates['quarantine_sha256'] = quarantineSha256;

    await _db!.update(
      'quran_audio_promotion_journal',
      updates,
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
    );
  }

  @override
  Future<void> deleteJournalEntry(int surahNumber, String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      _memJournals.remove('$reciterId:$surahNumber');
      return;
    }

    await _db!.delete(
      'quran_audio_promotion_journal',
      where: 'surah_number = ? AND reciter_id = ?',
      whereArgs: [surahNumber, reciterId],
    );
  }

  @override
  Future<void> finalizePromotion({
    required AudioDownloadModel download,
    required int surahNumber,
    required String reciterId,
  }) async {
    await init();
    if (_useInMemoryFallback) {
      _memDownloads['$reciterId:$surahNumber'] = download;
      _memJournals.remove('$reciterId:$surahNumber');
      return;
    }

    await _db!.transaction((txn) async {
      await txn.insert(
        'quran_audio_downloads',
        download.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'quran_audio_promotion_journal',
        where: 'surah_number = ? AND reciter_id = ?',
        whereArgs: [surahNumber, reciterId],
      );
    });
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

  // ---------------------------------------------------------------------------
  // Full-Quran Download Queue (QA.6 Phase 6.3)
  // ---------------------------------------------------------------------------

  @override
  Future<void> createQueue({
    required QuranDownloadQueueModel queue,
    required List<QuranDownloadQueueItemModel> items,
  }) async {
    await init();
    if (_useInMemoryFallback) {
      if (queue.status.isActive) {
        final existingActive = _memQueues.values.any((q) => q.status.isActive);
        if (existingActive) {
          throw StateError('Active queue already exists');
        }
      }
      _memQueues[queue.id] = queue;
      _memQueueItems[queue.id] = List.from(items);
      return;
    }

    await _db!.transaction((txn) async {
      await txn.insert(
        'quran_download_queues',
        queue.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'quran_download_queue_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<QuranDownloadQueueModel?> getActiveQueue() async {
    await init();
    if (_useInMemoryFallback) {
      try {
        final q = _memQueues.values.firstWhere((q) => q.status.isActive);
        final items = (_memQueueItems[q.id] ?? [])
            .map((i) => QuranDownloadQueueItemModel.fromEntity(i))
            .toList();
        return QuranDownloadQueueModel.fromEntity(q.copyWith(items: items));
      } catch (_) {
        return null;
      }
    }

    final maps = await _db!.query(
      'quran_download_queues',
      where: "status IN ('pending', 'running', 'paused')",
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final queueMap = maps.first;
    final queueId = queueMap['id'] as String;

    final itemMaps = await _db!.query(
      'quran_download_queue_items',
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'position ASC',
    );

    final items = itemMaps.map((m) => QuranDownloadQueueItemModel.fromMap(m)).toList();
    return QuranDownloadQueueModel.fromMap(queueMap, items);
  }

  @override
  Future<QuranDownloadQueueModel?> getQueueById(String queueId) async {
    await init();
    if (_useInMemoryFallback) {
      final q = _memQueues[queueId];
      if (q == null) return null;
      final items = (_memQueueItems[queueId] ?? [])
          .map((i) => QuranDownloadQueueItemModel.fromEntity(i))
          .toList();
      return QuranDownloadQueueModel.fromEntity(q.copyWith(items: items));
    }

    final maps = await _db!.query(
      'quran_download_queues',
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final itemMaps = await _db!.query(
      'quran_download_queue_items',
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'position ASC',
    );

    final items = itemMaps.map((m) => QuranDownloadQueueItemModel.fromMap(m)).toList();
    return QuranDownloadQueueModel.fromMap(maps.first, items);
  }

  @override
  Future<QuranDownloadQueueModel?> getLatestQueueForReciter(String reciterId) async {
    await init();
    if (_useInMemoryFallback) {
      final queues = _memQueues.values.where((q) => q.reciterId == reciterId).toList();
      if (queues.isEmpty) return null;
      queues.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final q = queues.first;
      final items = (_memQueueItems[q.id] ?? [])
          .map((i) => QuranDownloadQueueItemModel.fromEntity(i))
          .toList();
      return QuranDownloadQueueModel.fromEntity(q.copyWith(items: items));
    }

    final maps = await _db!.query(
      'quran_download_queues',
      where: 'reciter_id = ?',
      whereArgs: [reciterId],
      orderBy: 'updated_at DESC, created_at DESC, id DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final queueMap = maps.first;
    final queueId = queueMap['id'] as String;

    final itemMaps = await _db!.query(
      'quran_download_queue_items',
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'position ASC',
    );

    final items = itemMaps.map((m) => QuranDownloadQueueItemModel.fromMap(m)).toList();
    return QuranDownloadQueueModel.fromMap(queueMap, items);
  }

  @override
  Future<List<QuranDownloadQueueItemModel>> getQueueItems(String queueId) async {
    await init();
    if (_useInMemoryFallback) {
      final items = (_memQueueItems[queueId] ?? []).toList();
      items.sort((a, b) => a.position.compareTo(b.position));
      return items.map((i) => QuranDownloadQueueItemModel.fromEntity(i)).toList();
    }

    final maps = await _db!.query(
      'quran_download_queue_items',
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'position ASC',
    );

    return maps.map((m) => QuranDownloadQueueItemModel.fromMap(m)).toList();
  }

  @override
  Future<void> updateQueueStatus({
    required String queueId,
    required QuranDownloadQueueStatus status,
    DateTime? completedAt,
  }) async {
    await init();
    final nowIso = DateTime.now().toIso8601String();

    if (_useInMemoryFallback) {
      final q = _memQueues[queueId];
      if (q != null) {
        _memQueues[queueId] = q.copyWith(
          status: status,
          updatedAt: DateTime.parse(nowIso),
          completedAt: completedAt ?? (status.isCompleted ? DateTime.parse(nowIso) : q.completedAt),
        );
      }
      return;
    }

    final Map<String, dynamic> updates = {
      'status': status.toDbString(),
      'updated_at': nowIso,
    };
    if (completedAt != null) {
      updates['completed_at'] = completedAt.toIso8601String();
    } else if (status.isCompleted) {
      updates['completed_at'] = nowIso;
    }

    await _db!.update(
      'quran_download_queues',
      updates,
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  @override
  Future<void> updateQueueProgress({
    required String queueId,
    required int completedItems,
    required int downloadedBytes,
    int? totalExpectedBytes,
  }) async {
    await init();
    final nowIso = DateTime.now().toIso8601String();

    if (_useInMemoryFallback) {
      final q = _memQueues[queueId];
      if (q != null) {
        _memQueues[queueId] = q.copyWith(
          completedItems: completedItems,
          downloadedBytes: downloadedBytes,
          totalExpectedBytes: totalExpectedBytes ?? q.totalExpectedBytes,
          updatedAt: DateTime.parse(nowIso),
        );
      }
      return;
    }

    final Map<String, dynamic> updates = {
      'completed_items': completedItems,
      'downloaded_bytes': downloadedBytes,
      'updated_at': nowIso,
    };
    if (totalExpectedBytes != null) {
      updates['total_expected_bytes'] = totalExpectedBytes;
    }

    await _db!.update(
      'quran_download_queues',
      updates,
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  @override
  Future<void> updateQueueItemStatus({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueItemStatus status,
    int? downloadedBytes,
    String? lastError,
  }) async {
    await init();
    final nowIso = DateTime.now().toIso8601String();

    if (_useInMemoryFallback) {
      final items = _memQueueItems[queueId];
      if (items != null) {
        final idx = items.indexWhere((i) => i.surahNumber == surahNumber);
        if (idx != -1) {
          items[idx] = items[idx].copyWith(
            status: status,
            downloadedBytes: downloadedBytes ?? items[idx].downloadedBytes,
            lastError: lastError,
            updatedAt: DateTime.parse(nowIso),
          );
        }
      }
      return;
    }

    final Map<String, dynamic> updates = {
      'status': status.toDbString(),
      'updated_at': nowIso,
    };
    if (downloadedBytes != null) updates['downloaded_bytes'] = downloadedBytes;
    if (lastError != null) updates['last_error'] = lastError;

    await _db!.update(
      'quran_download_queue_items',
      updates,
      where: 'queue_id = ? AND surah_number = ?',
      whereArgs: [queueId, surahNumber],
    );
  }

  @override
  Future<void> updateQueueAndItemStatusAtomic({
    required String queueId,
    required int surahNumber,
    required QuranDownloadQueueStatus queueStatus,
    required QuranDownloadQueueItemStatus itemStatus,
    int? downloadedBytes,
    String? lastError,
  }) async {
    await init();
    final nowIso = DateTime.now().toIso8601String();

    if (_useInMemoryFallback) {
      await updateQueueItemStatus(
        queueId: queueId,
        surahNumber: surahNumber,
        status: itemStatus,
        downloadedBytes: downloadedBytes,
        lastError: lastError,
      );
      await updateQueueStatus(queueId: queueId, status: queueStatus);
      return;
    }

    await _db!.transaction((txn) async {
      final Map<String, dynamic> itemUpdates = {
        'status': itemStatus.toDbString(),
        'updated_at': nowIso,
      };
      if (downloadedBytes != null) itemUpdates['downloaded_bytes'] = downloadedBytes;
      if (lastError != null) itemUpdates['last_error'] = lastError;

      await txn.update(
        'quran_download_queue_items',
        itemUpdates,
        where: 'queue_id = ? AND surah_number = ?',
        whereArgs: [queueId, surahNumber],
      );

      final Map<String, dynamic> queueUpdates = {
        'status': queueStatus.toDbString(),
        'updated_at': nowIso,
      };
      if (queueStatus.isCompleted) {
        queueUpdates['completed_at'] = nowIso;
      }

      await txn.update(
        'quran_download_queues',
        queueUpdates,
        where: 'id = ?',
        whereArgs: [queueId],
      );
    });
  }

  @override
  Future<void> retryFailedQueueItems(String queueId) async {
    await init();
    final nowIso = DateTime.now().toIso8601String();

    if (_useInMemoryFallback) {
      final items = _memQueueItems[queueId];
      if (items != null) {
        for (int i = 0; i < items.length; i++) {
          if (items[i].status.isFailed) {
            items[i] = items[i].copyWith(
              status: QuranDownloadQueueItemStatus.pending,
              attemptCount: items[i].attemptCount + 1,
              clearLastError: true,
              updatedAt: DateTime.parse(nowIso),
            );
          }
        }
      }
      final q = _memQueues[queueId];
      if (q != null) {
        _memQueues[queueId] = q.copyWith(
          status: QuranDownloadQueueStatus.running,
          updatedAt: DateTime.parse(nowIso),
        );
      }
      return;
    }

    await _db!.transaction((txn) async {
      // 1. Reset all failed items to pending and increment attempt_count
      await txn.rawUpdate('''
        UPDATE quran_download_queue_items
        SET status = 'pending',
            attempt_count = attempt_count + 1,
            last_error = NULL,
            updated_at = ?
        WHERE queue_id = ? AND status = 'failed';
      ''', [nowIso, queueId]);

      // 2. Transition queue to running
      await txn.rawUpdate('''
        UPDATE quran_download_queues
        SET status = 'running',
            updated_at = ?
        WHERE id = ?;
      ''', [nowIso, queueId]);
    });
  }

  @override
  Future<void> deleteQueue(String queueId) async {
    await init();
    if (_useInMemoryFallback) {
      _memQueues.remove(queueId);
      _memQueueItems.remove(queueId);
      return;
    }

    await _db!.delete(
      'quran_download_queues',
      where: 'id = ?',
      whereArgs: [queueId],
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
