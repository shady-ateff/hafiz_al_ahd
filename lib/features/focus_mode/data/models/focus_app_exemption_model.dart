import '../../domain/entities/installed_app_info.dart';

class FocusAppExemptionModel {
  final String packageName;
  final String appName;
  final int isExempt;
  final int isSystemCritical;
  final int updatedAt;

  const FocusAppExemptionModel({
    required this.packageName,
    required this.appName,
    required this.isExempt,
    required this.isSystemCritical,
    required this.updatedAt,
  });

  factory FocusAppExemptionModel.fromEntity(InstalledAppInfo entity) {
    return FocusAppExemptionModel(
      packageName: entity.packageName,
      appName: entity.appName,
      isExempt: entity.isExempt ? 1 : 0,
      isSystemCritical: entity.isSystemCritical ? 1 : 0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  InstalledAppInfo toEntity({String? iconBase64, bool isSystemApp = false}) {
    return InstalledAppInfo(
      packageName: packageName,
      appName: appName,
      isSystemApp: isSystemApp,
      isSystemCritical: isSystemCritical == 1,
      isExempt: isExempt == 1,
      iconBase64: iconBase64,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'package_name': packageName,
      'app_name': appName,
      'is_exempt': isExempt,
      'is_system_critical': isSystemCritical,
      'updated_at': updatedAt,
    };
  }

  factory FocusAppExemptionModel.fromMap(Map<String, dynamic> map) {
    return FocusAppExemptionModel(
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String,
      isExempt: (map['is_exempt'] as num).toInt(),
      isSystemCritical: (map['is_system_critical'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
    );
  }
}
