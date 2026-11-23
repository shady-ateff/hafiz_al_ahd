import '../entities/focus_enforcement_status.dart';

/// Abstract domain port representing the enforcement mechanism (Shield, Service, Monitoring).
///
/// Keeps the Domain Layer completely isolated from Android Platform APIs,
/// Foreground Services, and MethodChannels.
abstract class FocusEnforcementPort {
  /// Initiates external enforcement with the specified [sessionId] and [wardTitle].
  /// Returns `true` if enforcement started successfully.
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  });

  /// Terminates external enforcement (dismantles shield, stops service).
  /// Returns `true` if enforcement stopped cleanly, `false` otherwise.
  Future<bool> stopEnforcement();

  /// Checks whether external enforcement is actively running.
  Future<bool> isEnforcing();

  /// Queries the detailed status of the native enforcement service,
  /// including the active [sessionId] for state reconciliation.
  Future<FocusEnforcementStatus> getEnforcementStatus();
}
