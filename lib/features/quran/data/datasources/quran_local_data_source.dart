import 'dart:convert';
import 'dart:developer';
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
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
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
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = _initDatabaseCore();
    await _initFuture;
  }

  Future<void> _initDatabaseCore() async {
    final db = await database;
    
    // تأكد إذا كانت الداتا بيز مليانة ولا فاضية
    int count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM quran_pages'),
    ) ?? 0;

    // لو حصل تكرار بسبب الـ Concurrency في التشغيلة اللي فاتت أو لو حصل Seed ناقص
    if (count > 6240 || (count > 0 && count < 6000)) {
      log("⚠️ Corrupted or partial Quran DB detected (count: $count). Resetting...");
      await db.delete('quran_pages');
      count = 0;
    }

    if (count == 0) {
      log("⏳ Seeding Quran database from quran_lines.json...");
      await _seedDatabase(db);
      log("✅ Quran database seeded successfully.");
    } else {
      log("✅ Quran database already seeded. Lines count: $count");
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

        int currentLineNumber = 1;
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
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'quran_pages',
      where: 'page_number = ?',
      whereArgs: [pageNumber],
      orderBy: 'line_number ASC',
    );

    if (maps.isEmpty) {
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
  }
}
