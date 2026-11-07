import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/quran_page_model.dart';

abstract class BaseQuranLocalDataSource {
  Future<void> initDatabase();
  Future<QuranPageModel> getPage(int pageNumber);
}

class QuranLocalDataSourceImpl implements BaseQuranLocalDataSource {
  static Database? _database;
  static Map<int, QuranPageModel>? _inMemoryPages;
  static Future<void>? _loadPagesFuture;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _loadPagesFromAsset() async {
    if (_inMemoryPages != null && _inMemoryPages!.isNotEmpty) return;
    if (_loadPagesFuture != null) {
      await _loadPagesFuture;
      return;
    }

    _loadPagesFuture = _loadPagesFromAssetCore();
    await _loadPagesFuture;
  }

  Future<void> _loadPagesFromAssetCore() async {
    if (_inMemoryPages != null && _inMemoryPages!.isNotEmpty) return;
    try {
      final String jsonData =
          await rootBundle.loadString('assets/quran/mushaf/quran_lines.json');
      final List<dynamic> pages = jsonDecode(jsonData);
      final Map<int, QuranPageModel> map = {};

      for (var pageObj in pages) {
        final int pageNumber = pageObj['page_number'] as int;
        final List<dynamic> linesList = pageObj['lines'] as List<dynamic>;

        final List<QuranLineModel> lines = [];
        for (var line in linesList) {
          lines.add(QuranLineModel(
            lineNumber: line['line_number'] as int,
            surahNumber: line['surah_number'] as int,
            text: line['text'].toString().trim(),
          ));
        }

        map[pageNumber] = QuranPageModel(
          pageNumber: pageNumber,
          lines: lines,
        );
      }
      _inMemoryPages = map;
      log("✅ Loaded ${_inMemoryPages!.length} Quran pages into in-memory cache.");
    } catch (e) {
      log("❌ Error loading Quran pages from asset: $e");
      rethrow;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('quran.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute('DROP TABLE IF EXISTS quran_pages');
          await _createDB(db, newVersion);
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE quran_pages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        page_number INTEGER NOT NULL,
        line_number INTEGER NOT NULL,
        surah_number INTEGER NOT NULL,
        text_qcf TEXT NOT NULL
      )
    ''');
    log("✅ quran_pages table created successfully.");
  }

  Future<void>? _initFuture;

  @override
  Future<void> initDatabase() async {
    if (_isDesktop) {
      log("🖥️ Desktop platform detected: Initializing in-memory Quran cache...");
      await _loadPagesFromAsset();
      return;
    }

    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = _initDatabaseCore();
    await _initFuture;
  }

  Future<void> _initDatabaseCore() async {
    try {
      final db = await database;
      
      int count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM quran_pages'),
      ) ?? 0;

      if (count == 0) {
        log("⏳ Seeding Quran database from quran_lines.json...");
        await _seedDatabase(db);
        log("✅ Quran database seeded successfully.");
      } else {
        log("✅ Quran database already seeded. Lines count: $count");
      }
    } catch (e) {
      log("⚠️ SQLite init failed, falling back to asset loader: $e");
      await _loadPagesFromAsset();
    }
  }

  Future<void> _seedDatabase(Database db) async {
    try {
      final String jsonData = await rootBundle.loadString('assets/quran/mushaf/quran_lines.json');
      final List<dynamic> pages = jsonDecode(jsonData);

      Batch batch = db.batch();

      for (var pageObj in pages) {
        final int pageNumber = pageObj['page_number'] as int;
        final List<dynamic> lines = pageObj['lines'] as List<dynamic>;

        for (var line in lines) {
          final String textQcf = line['text'].toString().trim();
          final int lineNumber = line['line_number'] as int;
          final int surahNumber = line['surah_number'] as int;

          if (textQcf.isNotEmpty) {
            batch.insert('quran_pages', {
              'page_number': pageNumber,
              'line_number': lineNumber,
              'surah_number': surahNumber,
              'text_qcf': textQcf,
            });
          }
        }
      }

      await batch.commit(noResult: true);
    } catch (e) {
      log("❌ Error seeding Quran Database: $e");
    }
  }

  @override
  Future<QuranPageModel> getPage(int pageNumber) async {
    // 1. If running on desktop, strictly use in-memory asset loader.
    // sqflite does not support Windows/Linux/macOS desktop without sqflite_common_ffi native setup.
    if (_isDesktop) {
      await _loadPagesFromAsset();
      final page = _inMemoryPages?[pageNumber];
      if (page != null) return page;
      throw Exception("Page $pageNumber not found in Quran asset cache");
    }

    // 2. If in-memory pages are already cached, use them directly
    if (_inMemoryPages != null && _inMemoryPages!.containsKey(pageNumber)) {
      return _inMemoryPages![pageNumber]!;
    }

    // 3. For mobile platforms (Android/iOS), query SQLite with asset fallback
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'quran_pages',
        where: 'page_number = ?',
        whereArgs: [pageNumber],
        orderBy: 'line_number ASC',
      );

      if (maps.isEmpty) {
        await _loadPagesFromAsset();
        final fallbackPage = _inMemoryPages?[pageNumber];
        if (fallbackPage != null) return fallbackPage;
        throw Exception("Page $pageNumber not found");
      }

      final List<QuranLineModel> lines = maps.map((map) {
        return QuranLineModel(
          lineNumber: map['line_number'] as int,
          surahNumber: map['surah_number'] as int,
          text: map['text_qcf'] as String,
        );
      }).toList();

      return QuranPageModel(
        pageNumber: pageNumber,
        lines: lines,
      );
    } catch (e) {
      log("⚠️ getPage SQLite query failed, falling back to asset: $e");
      await _loadPagesFromAsset();
      final page = _inMemoryPages?[pageNumber];
      if (page != null) return page;
      throw Exception("Page $pageNumber not found");
    }
  }
}
