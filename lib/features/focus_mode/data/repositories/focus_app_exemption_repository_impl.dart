import '../../domain/entities/installed_app_info.dart';
import '../../domain/repositories/focus_app_exemption_repository.dart';
import '../datasources/focus_app_exemption_local_data_source.dart';
import '../models/focus_app_exemption_model.dart';

class FocusAppExemptionRepositoryImpl implements FocusAppExemptionRepository {
  final FocusAppExemptionLocalDataSource localDataSource;

  FocusAppExemptionRepositoryImpl({required this.localDataSource});

  @override
  Future<void> saveExemptions(List<InstalledAppInfo> apps) async {
    final models = apps.map((a) => FocusAppExemptionModel.fromEntity(a)).toList();
    await localDataSource.saveAllExemptions(models);
  }

  @override
  Future<List<InstalledAppInfo>> getAllSavedExemptions() async {
    final models = await localDataSource.getAllExemptions();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Set<String>> getExemptPackageNames() async {
    final list = await localDataSource.getExemptPackageNames();
    return list.toSet();
  }

  @override
  Future<void> setAppExemption({
    required String packageName,
    required bool isExempt,
    String? appName,
    bool isSystemCritical = false,
  }) async {
    final existing = await localDataSource.getExemption(packageName);
    final model = FocusAppExemptionModel(
      packageName: packageName,
      appName: appName ?? existing?.appName ?? packageName,
      isExempt: isExempt ? 1 : 0,
      isSystemCritical: isSystemCritical ? 1 : (existing?.isSystemCritical ?? 0),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await localDataSource.saveExemption(model);
  }

  @override
  Future<void> clearExemptions() async {
    await localDataSource.clearExemptions();
  }
}
