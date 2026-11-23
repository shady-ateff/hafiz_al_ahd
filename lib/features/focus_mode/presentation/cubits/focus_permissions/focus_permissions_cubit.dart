import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'focus_permissions_state.dart';

class FocusPermissionsCubit extends Cubit<FocusPermissionsState> {
  static const MethodChannel _channel =
      MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');

  final MethodChannel channel;

  FocusPermissionsCubit({MethodChannel? customChannel})
      : channel = customChannel ?? _channel,
        super(const FocusPermissionsState());

  Future<void> checkPermissions() async {
    emit(state.copyWith(isLoading: true));
    try {
      final permissions =
          await channel.invokeMapMethod<String, dynamic>('checkPermissions');

      emit(state.copyWith(
        hasUsageAccess: permissions?['hasUsageAccess'] as bool? ?? false,
        hasOverlayPermission:
            permissions?['hasOverlayPermission'] as bool? ?? false,
        canScheduleExactAlarms:
            permissions?['canScheduleExactAlarms'] as bool? ?? false,
        isLoading: false,
      ));
    } catch (_) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await channel.invokeMethod<void>('openUsageAccessSettings');
    } catch (_) {}
  }

  Future<void> openOverlaySettings() async {
    try {
      await channel.invokeMethod<void>('openOverlaySettings');
    } catch (_) {}
  }

  Future<void> openExactAlarmSettings() async {
    try {
      await channel.invokeMethod<void>('openExactAlarmSettings');
    } catch (_) {}
  }
}
