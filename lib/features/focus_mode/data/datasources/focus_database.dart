import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database management for the Focus Mode subsystem.
/// Provides schemas and transactional access for sessions, progress, and operations.
class FocusDatabase {
  static const String databaseName = 'focus_mode.db';
  static const int databaseVersion = 3;

  final Database? _injectedDb;
  Database? _db;

  FocusDatabase({Database? injectedDb}) : _injectedDb = injectedDb;

  Future<Database> get database async {
    if (_injectedDb != null) return _injectedDb;
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, databaseName);

    return await openDatabase(
      path,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 1. Table for focus sessions
    await db.execute('''
      CREATE TABLE focus_sessions (
        session_id TEXT PRIMARY KEY,
        ward_type TEXT NOT NULL,
        status TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        snooze_count INTEGER NOT NULL DEFAULT 0,
        max_snooze_count INTEGER NOT NULL DEFAULT 2,
        interruption_reason TEXT,
        enforcement_stop_failed INTEGER NOT NULL DEFAULT 0,
        quran_goal_json TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 2. Table for cumulative progress
    await db.execute('''
      CREATE TABLE focus_session_progress (
        session_id TEXT PRIMARY KEY,
        required_item_keys TEXT NOT NULL,
        completed_item_keys TEXT NOT NULL,
        read_quran_pages TEXT NOT NULL,
        accumulated_quran_duration_ms INTEGER NOT NULL DEFAULT 0,
        last_completed_page INTEGER,
        quran_goal_snapshot_json TEXT,
        session_version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES focus_sessions (session_id) ON DELETE CASCADE
      )
    ''');

    // 3. Table for pending enforcement operations (Start / Stop / Snooze)
    await db.execute('''
      CREATE TABLE focus_enforcement_operations (
        operation_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_attempt_at INTEGER,
        last_error TEXT
      )
    ''');

    // 4. Table for scheduled focus rules
    await db.execute('''
      CREATE TABLE focus_schedules (
        id TEXT PRIMARY KEY,
        ward_type TEXT NOT NULL,
        title TEXT NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        days_of_week TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        pre_notification_minutes INTEGER NOT NULL DEFAULT 0,
        quran_goal_json TEXT,
        last_triggered_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 5. Table for app exemptions
    await db.execute('''
      CREATE TABLE focus_app_exemptions (
        package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        is_exempt INTEGER NOT NULL DEFAULT 0,
        is_system_critical INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Indexes
    await db.execute('''
      CREATE INDEX idx_focus_sessions_active ON focus_sessions (is_active, status);
    ''');
    await db.execute('''
      CREATE INDEX idx_focus_operations_status ON focus_enforcement_operations (status);
    ''');
    await db.execute('''
      CREATE INDEX idx_focus_schedules_enabled ON focus_schedules (is_enabled);
    ''');
    await db.execute('''
      CREATE INDEX idx_focus_app_exemptions_is_exempt ON focus_app_exemptions (is_exempt);
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS focus_schedules (
          id TEXT PRIMARY KEY,
          ward_type TEXT NOT NULL,
          title TEXT NOT NULL,
          hour INTEGER NOT NULL,
          minute INTEGER NOT NULL,
          days_of_week TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          pre_notification_minutes INTEGER NOT NULL DEFAULT 0,
          quran_goal_json TEXT,
          last_triggered_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_focus_schedules_enabled ON focus_schedules (is_enabled);
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS focus_app_exemptions (
          package_name TEXT PRIMARY KEY,
          app_name TEXT NOT NULL,
          is_exempt INTEGER NOT NULL DEFAULT 0,
          is_system_critical INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_focus_app_exemptions_is_exempt ON focus_app_exemptions (is_exempt);
      ''');
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
