import 'package:sqflite/sqflite.dart';
import '../models/focus_schedule_model.dart';
import 'focus_database.dart';

abstract class FocusScheduleLocalDataSource {
  Future<void> saveSchedule(FocusScheduleModel schedule);
  Future<FocusScheduleModel?> getScheduleById(String id);
  Future<List<FocusScheduleModel>> getAllSchedules();
  Future<List<FocusScheduleModel>> getEnabledSchedules();
  Future<void> deleteSchedule(String id);
  Future<void> updateScheduleStatus(String id, int isEnabled);
  Future<void> recordTrigger(String id, int triggeredAtMillis);
}

class FocusScheduleLocalDataSourceImpl implements FocusScheduleLocalDataSource {
  final FocusDatabase? focusDatabase;
  final bool _isInMemory;

  // In-memory store for hermetic testing
  final Map<String, FocusScheduleModel> _memStore = {};

  FocusScheduleLocalDataSourceImpl({required this.focusDatabase})
      : _isInMemory = false;

  /// In-memory constructor for unit testing without C-library SQLite dependencies
  FocusScheduleLocalDataSourceImpl.inMemory()
      : focusDatabase = null,
        _isInMemory = true;

  Future<Database> _getDb() async {
    if (focusDatabase == null) {
      throw StateError('FocusDatabase is null in non-inMemory mode');
    }
    return await focusDatabase!.database;
  }

  @override
  Future<void> saveSchedule(FocusScheduleModel schedule) async {
    if (_isInMemory) {
      _memStore[schedule.id] = schedule;
      return;
    }

    final db = await _getDb();
    await db.insert(
      'focus_schedules',
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<FocusScheduleModel?> getScheduleById(String id) async {
    if (_isInMemory) {
      return _memStore[id];
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_schedules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return FocusScheduleModel.fromMap(results.first);
  }

  @override
  Future<List<FocusScheduleModel>> getAllSchedules() async {
    if (_isInMemory) {
      return _memStore.values.toList();
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_schedules',
      orderBy: 'hour ASC, minute ASC',
    );

    return results.map((e) => FocusScheduleModel.fromMap(e)).toList();
  }

  @override
  Future<List<FocusScheduleModel>> getEnabledSchedules() async {
    if (_isInMemory) {
      return _memStore.values.where((s) => s.isEnabled == 1).toList();
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_schedules',
      where: 'is_enabled = ?',
      whereArgs: [1],
      orderBy: 'hour ASC, minute ASC',
    );

    return results.map((e) => FocusScheduleModel.fromMap(e)).toList();
  }

  @override
  Future<void> deleteSchedule(String id) async {
    if (_isInMemory) {
      _memStore.remove(id);
      return;
    }

    final db = await _getDb();
    await db.delete(
      'focus_schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> updateScheduleStatus(String id, int isEnabled) async {
    if (_isInMemory) {
      final existing = _memStore[id];
      if (existing != null) {
        _memStore[id] = FocusScheduleModel(
          id: existing.id,
          wardType: existing.wardType,
          title: existing.title,
          hour: existing.hour,
          minute: existing.minute,
          daysOfWeekJson: existing.daysOfWeekJson,
          isEnabled: isEnabled,
          preNotificationMinutes: existing.preNotificationMinutes,
          quranGoalJson: existing.quranGoalJson,
          lastTriggeredAt: existing.lastTriggeredAt,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return;
    }

    final db = await _getDb();
    await db.update(
      'focus_schedules',
      {
        'is_enabled': isEnabled,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordTrigger(String id, int triggeredAtMillis) async {
    if (_isInMemory) {
      final existing = _memStore[id];
      if (existing != null) {
        _memStore[id] = FocusScheduleModel(
          id: existing.id,
          wardType: existing.wardType,
          title: existing.title,
          hour: existing.hour,
          minute: existing.minute,
          daysOfWeekJson: existing.daysOfWeekJson,
          isEnabled: existing.isEnabled,
          preNotificationMinutes: existing.preNotificationMinutes,
          quranGoalJson: existing.quranGoalJson,
          lastTriggeredAt: triggeredAtMillis,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return;
    }

    final db = await _getDb();
    await db.update(
      'focus_schedules',
      {
        'last_triggered_at': triggeredAtMillis,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
