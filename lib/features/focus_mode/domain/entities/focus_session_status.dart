/// Represents the discrete states of a Focus Mode session lifecycle.
enum FocusSessionStatus {
  /// No session is running.
  idle,

  /// Focus session is active and shield actively guards distractions.
  active,

  /// Session is temporarily paused via Snooze (max 2 times, 5 minutes each).
  snoozed,

  /// Session successfully completed because the user finished the genuine ward.
  completed,

  /// Session cancelled intentionally by the user from within Hafiz Al-Ahd.
  cancelled,

  /// Session was abnormally interrupted (process killed, permissions revoked, device restart).
  interrupted,
}

extension FocusSessionStatusExtension on FocusSessionStatus {
  bool get isEnforcing =>
      this == FocusSessionStatus.active || this == FocusSessionStatus.snoozed;

  bool get isTerminal =>
      this == FocusSessionStatus.completed ||
      this == FocusSessionStatus.cancelled ||
      this == FocusSessionStatus.interrupted;
}
