import 'package:sqflite/sqflite.dart';
import '../models/focus_app_exemption_model.dart';
import 'focus_database.dart';

abstract class FocusAppExemptionLocalDataSource {
  Future<void> saveExemption(FocusAppExemptionModel model);
  Future<void> saveAllExemptions(List<FocusAppExemptionModel> models);
  Future<List<FocusAppExemptionModel>> getAllExemptions();
  Future<List<String>> getExemptPackageNames();
  Future<FocusAppExemptionModel?> getExemption(String packageName);
  Future<void> clearExemptions();
}

class FocusAppExemptionLocalDataSourceImpl
    implements FocusAppExemptionLocalDataSource {
  final FocusDatabase? focusDatabase;
  final bool _isInMemory;

  // In-memory store for hermetic tests
  final Map<String, FocusAppExemptionModel> _memStore = {};

  FocusAppExemptionLocalDataSourceImpl({required this.focusDatabase})
      : _isInMemory = false;

  FocusAppExemptionLocalDataSourceImpl.inMemory()
      : focusDatabase = null,
        _isInMemory = true;

  Future<Database> _getDb() async {
    if (focusDatabase == null) {
      throw StateError('FocusDatabase is null in non-inMemory mode');
    }
    return await focusDatabase!.database;
  }

  @override
  Future<void> saveExemption(FocusAppExemptionModel model) async {
    if (_isInMemory) {
      _memStore[model.packageName] = model;
      return;
    }

    final db = await _getDb();
    await db.insert(
      'focus_app_exemptions',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveAllExemptions(List<FocusAppExemptionModel> models) async {
    if (_isInMemory) {
      for (final m in models) {
        _memStore[m.packageName] = m;
      }
      return;
    }

    final db = await _getDb();
    await db.transaction((txn) async {
      for (final m in models) {
        await txn.insert(
          'focus_app_exemptions',
          m.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<FocusAppExemptionModel>> getAllExemptions() async {
    if (_isInMemory) {
      return _memStore.values.toList();
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_app_exemptions',
      orderBy: 'app_name ASC',
    );

    return results.map((e) => FocusAppExemptionModel.fromMap(e)).toList();
  }

  @override
  Future<List<String>> getExemptPackageNames() async {
    if (_isInMemory) {
      return _memStore.values
          .where((e) => e.isExempt == 1)
          .map((e) => e.packageName)
          .toList();
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_app_exemptions',
      columns: ['package_name'],
      where: 'is_exempt = ?',
      whereArgs: [1],
    );

    return results.map((e) => e['package_name'] as String).toList();
  }

  @override
  Future<FocusAppExemptionModel?> getExemption(String packageName) async {
    if (_isInMemory) {
      return _memStore[packageName];
    }

    final db = await _getDb();
    final results = await db.query(
      'focus_app_exemptions',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return FocusAppExemptionModel.fromMap(results.first);
  }

  @override
  Future<void> clearExemptions() async {
    if (_isInMemory) {
      _memStore.clear();
      return;
    }

    final db = await _getDb();
    await db.delete('focus_app_exemptions');
  }
}
