import 'package:equatable/equatable.dart';
import '../../../domain/entities/focus_schedule.dart';
import '../../../domain/entities/focus_session_state.dart';
import '../../../domain/entities/focus_session_status.dart';

class FocusSettingsState extends Equatable {
  final bool isFocusModeMasterEnabled;
  final List<FocusSchedule> schedules;
  final FocusSessionState? activeSession;
  final int exemptAppsCount;
  final bool isLoading;
  final String? errorMessage;

  const FocusSettingsState({
    this.isFocusModeMasterEnabled = false,
    this.schedules = const [],
    this.activeSession,
    this.exemptAppsCount = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get hasActiveSession =>
      activeSession != null && activeSession!.status.isEnforcing;

  int get maxSnoozeCount => activeSession?.maxSnoozeCount ?? 2;
  int get currentSnoozeCount => activeSession?.snoozeCount ?? 0;
  int get remainingSnoozeCount =>
      (maxSnoozeCount - currentSnoozeCount).clamp(0, maxSnoozeCount);

  FocusSettingsState copyWith({
    bool? isFocusModeMasterEnabled,
    List<FocusSchedule>? schedules,
    FocusSessionState? activeSession,
    bool clearActiveSession = false,
    int? exemptAppsCount,
    bool? isLoading,
    String? errorMessage,
  }) {
    return FocusSettingsState(
      isFocusModeMasterEnabled:
          isFocusModeMasterEnabled ?? this.isFocusModeMasterEnabled,
      schedules: schedules ?? this.schedules,
      activeSession:
          clearActiveSession ? null : (activeSession ?? this.activeSession),
      exemptAppsCount: exemptAppsCount ?? this.exemptAppsCount,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isFocusModeMasterEnabled,
        schedules,
        activeSession,
        exemptAppsCount,
        isLoading,
        errorMessage,
      ];
}
