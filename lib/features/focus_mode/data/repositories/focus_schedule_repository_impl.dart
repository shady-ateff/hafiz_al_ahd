import '../../domain/entities/focus_schedule.dart';
import '../../domain/repositories/focus_schedule_repository.dart';
import '../datasources/focus_schedule_local_data_source.dart';
import '../models/focus_schedule_model.dart';

class FocusScheduleRepositoryImpl implements FocusScheduleRepository {
  final FocusScheduleLocalDataSource localDataSource;

  FocusScheduleRepositoryImpl({required this.localDataSource});

  @override
  Future<void> saveSchedule(FocusSchedule schedule) async {
    final model = FocusScheduleModel.fromEntity(schedule);
    await localDataSource.saveSchedule(model);
  }

  @override
  Future<FocusSchedule?> getScheduleById(String id) async {
    final model = await localDataSource.getScheduleById(id);
    return model?.toEntity();
  }

  @override
  Future<List<FocusSchedule>> getAllSchedules() async {
    final models = await localDataSource.getAllSchedules();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<FocusSchedule>> getEnabledSchedules() async {
    final models = await localDataSource.getEnabledSchedules();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> deleteSchedule(String id) async {
    await localDataSource.deleteSchedule(id);
  }

  @override
  Future<void> updateScheduleStatus(String id, bool isEnabled) async {
    await localDataSource.updateScheduleStatus(id, isEnabled ? 1 : 0);
  }

  @override
  Future<void> recordTrigger(String id, DateTime triggeredAt) async {
    await localDataSource.recordTrigger(
      id,
      triggeredAt.millisecondsSinceEpoch,
    );
  }
}
