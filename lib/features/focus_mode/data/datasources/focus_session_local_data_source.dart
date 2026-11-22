import 'package:sqflite/sqflite.dart';
import '../../domain/entities/focus_enforcement_operation.dart';
import '../models/focus_enforcement_operation_model.dart';
import '../models/focus_session_model.dart';
import '../models/focus_session_progress_model.dart';
import 'focus_database.dart';

abstract class FocusSessionLocalDataSource {
  Future<void> saveActiveSession(
    FocusSessionModel session, {
    FocusSessionProgressModel? progress,
    FocusEnforcementOperationModel? pendingOperation,
  });

  Future<FocusSessionModel?> getActiveSession();

  Future<void> clearActiveSession();

  Future<void> saveProgress(FocusSessionProgressModel progress);

  Future<FocusSessionProgressModel?> getProgress(String sessionId);

  Future<void> archiveSession(
    FocusSessionModel session, {
    FocusEnforcementOperationModel? pendingOperation,
  });

  Future<List<FocusSessionModel>> getSessionHistory({int limit = 20});

  Future<void> saveEnforcementOperation(
      FocusEnforcementOperationModel operation);

  Future<List<FocusEnforcementOperationModel>>
      getPendingEnforcementOperations();

  Future<void> updateEnforcementOperationStatus({
    required String operationId,
    required String status,
    String? error,
  });

  Future<void> deleteEnforcementOperation(String operationId);
}

class FocusSessionLocalDataSourceImpl implements FocusSessionLocalDataSource {
  final FocusDatabase? focusDatabase;
  final bool _isInMemory;

  // In-memory atomic store for hermetic host testing
  final Map<String, FocusSessionModel> _memSessions = {};
  String? _memActiveSessionId;
  final Map<String, FocusSessionProgressModel> _memProgress = {};
  final Map<String, FocusEnforcementOperationModel> _memOperations = {};

  FocusSessionLocalDataSourceImpl({required FocusDatabase this.focusDatabase})
      : _isInMemory = false;

  FocusSessionLocalDataSourceImpl.inMemory()
      : focusDatabase = null,
        _isInMemory = true;

  @override
  Future<void> saveActiveSession(
    FocusSessionModel session, {
    FocusSessionProgressModel? progress,
    FocusEnforcementOperationModel? pendingOperation,
  }) async {
    if (_isInMemory) {
      _memActiveSessionId = session.sessionId;
      _memSessions[session.sessionId] = session;
      if (progress != null) {
        _memProgress[session.sessionId] = progress;
      }
      if (pendingOperation != null) {
        _memOperations[pendingOperation.operationId] = pendingOperation;
      }
      return;
    }

    final db = await focusDatabase!.database;
    await db.transaction((txn) async {
      await txn.update(
        'focus_sessions',
        {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'is_active = 1',
      );

      await txn.insert(
        'focus_sessions',
        session.toDbMap(isActive: 1),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (progress != null) {
        await txn.insert(
          'focus_session_progress',
          progress.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (pendingOperation != null) {
        await txn.insert(
          'focus_enforcement_operations',
          pendingOperation.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<FocusSessionModel?> getActiveSession() async {
    if (_isInMemory) {
      if (_memActiveSessionId == null) return null;
      return _memSessions[_memActiveSessionId];
    }

    final db = await focusDatabase!.database;
    final results = await db.query(
      'focus_sessions',
      where: 'is_active = 1',
      limit: 1,
    );

    if (results.isNotEmpty) {
      return FocusSessionModel.fromDbMap(results.first);
    }
    return null;
  }

  @override
  Future<void> clearActiveSession() async {
    if (_isInMemory) {
      _memActiveSessionId = null;
      return;
    }

    final db = await focusDatabase!.database;
    await db.update(
      'focus_sessions',
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'is_active = 1',
    );
  }

  @override
  Future<void> saveProgress(FocusSessionProgressModel progress) async {
    if (_isInMemory) {
      _memProgress[progress.sessionId] = progress;
      return;
    }

    final db = await focusDatabase!.database;
    await db.insert(
      'focus_session_progress',
      progress.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<FocusSessionProgressModel?> getProgress(String sessionId) async {
    if (_isInMemory) {
      return _memProgress[sessionId];
    }

    final db = await focusDatabase!.database;
    final results = await db.query(
      'focus_session_progress',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return FocusSessionProgressModel.fromDbMap(results.first);
    }
    return null;
  }

  @override
  Future<void> archiveSession(
    FocusSessionModel session, {
    FocusEnforcementOperationModel? pendingOperation,
  }) async {
    if (_isInMemory) {
      _memSessions[session.sessionId] = session;
      if (_memActiveSessionId == session.sessionId) {
        _memActiveSessionId = null;
      }
      if (pendingOperation != null) {
        _memOperations[pendingOperation.operationId] = pendingOperation;
      }
      return;
    }

    final db = await focusDatabase!.database;
    await db.transaction((txn) async {
      await txn.insert(
        'focus_sessions',
        session.toDbMap(isActive: 0),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (pendingOperation != null) {
        await txn.insert(
          'focus_enforcement_operations',
          pendingOperation.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<FocusSessionModel>> getSessionHistory({int limit = 20}) async {
    if (_isInMemory) {
      final archived = _memSessions.values
          .where((s) => s.sessionId != _memActiveSessionId)
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      return archived.take(limit).toList();
    }

    final db = await focusDatabase!.database;
    final results = await db.query(
      'focus_sessions',
      where: 'is_active = 0',
      orderBy: 'start_time DESC',
      limit: limit,
    );

    return results.map((m) => FocusSessionModel.fromDbMap(m)).toList();
  }

  @override
  Future<void> saveEnforcementOperation(
      FocusEnforcementOperationModel operation) async {
    if (_isInMemory) {
      _memOperations[operation.operationId] = operation;
      return;
    }

    final db = await focusDatabase!.database;
    await db.insert(
      'focus_enforcement_operations',
      operation.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<FocusEnforcementOperationModel>>
      getPendingEnforcementOperations() async {
    if (_isInMemory) {
      return _memOperations.values
          .where((op) =>
              op.status.name == 'pending' || op.status.name == 'failed')
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final db = await focusDatabase!.database;
    final results = await db.query(
      'focus_enforcement_operations',
      where: 'status = ? OR status = ?',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
    );

    return results
        .map((m) => FocusEnforcementOperationModel.fromDbMap(m))
        .toList();
  }

  @override
  Future<void> updateEnforcementOperationStatus({
    required String operationId,
    required String status,
    String? error,
  }) async {
    if (_isInMemory) {
      final existing = _memOperations[operationId];
      if (existing != null) {
        final updatedEntity = existing.copyWith(
          status: status == 'completed'
              ? EnforcementOperationStatus.completed
              : (status == 'failed'
                  ? EnforcementOperationStatus.failed
                  : EnforcementOperationStatus.executing),
          retryCount: existing.retryCount + 1,
          lastAttemptAt: DateTime.now(),
          lastError: error,
        );
        _memOperations[operationId] =
            FocusEnforcementOperationModel.fromEntity(updatedEntity);
      }
      return;
    }

    final db = await focusDatabase!.database;
    await db.rawUpdate('''
      UPDATE focus_enforcement_operations
      SET status = ?,
          last_error = ?,
          last_attempt_at = ?,
          retry_count = retry_count + 1
      WHERE operation_id = ?
    ''', [
      status,
      error,
      DateTime.now().millisecondsSinceEpoch,
      operationId,
    ]);
  }

  @override
  Future<void> deleteEnforcementOperation(String operationId) async {
    if (_isInMemory) {
      _memOperations.remove(operationId);
      return;
    }

    final db = await focusDatabase!.database;
    await db.delete(
      'focus_enforcement_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }
}
