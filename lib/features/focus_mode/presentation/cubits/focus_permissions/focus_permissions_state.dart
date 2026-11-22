import 'package:equatable/equatable.dart';

class FocusPermissionsState extends Equatable {
  final bool hasUsageAccess;
  final bool hasOverlayPermission;
  final bool canScheduleExactAlarms;
  final bool isLoading;

  const FocusPermissionsState({
    this.hasUsageAccess = false,
    this.hasOverlayPermission = false,
    this.canScheduleExactAlarms = false,
    this.isLoading = false,
  });

  bool get isAllGranted =>
      hasUsageAccess && hasOverlayPermission && canScheduleExactAlarms;

  FocusPermissionsState copyWith({
    bool? hasUsageAccess,
    bool? hasOverlayPermission,
    bool? canScheduleExactAlarms,
    bool? isLoading,
  }) {
    return FocusPermissionsState(
      hasUsageAccess: hasUsageAccess ?? this.hasUsageAccess,
      hasOverlayPermission:
          hasOverlayPermission ?? this.hasOverlayPermission,
      canScheduleExactAlarms:
          canScheduleExactAlarms ?? this.canScheduleExactAlarms,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
        hasUsageAccess,
        hasOverlayPermission,
        canScheduleExactAlarms,
        isLoading,
      ];
}
