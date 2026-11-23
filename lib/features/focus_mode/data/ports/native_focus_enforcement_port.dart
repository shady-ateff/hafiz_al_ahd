import '../../../focus_mode_poc/data/focus_poc_channel.dart';
import '../../domain/entities/focus_enforcement_status.dart';
import '../../domain/ports/focus_enforcement_port.dart';

/// Concrete implementation of [FocusEnforcementPort] using the Native Android Engine.
///
/// Encapsulates all MethodChannel calls, keeping the Domain Layer pure.
class NativeFocusEnforcementPort implements FocusEnforcementPort {
  const NativeFocusEnforcementPort();

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async {
    try {
      return await FocusPoCChannel.startMonitoring(
        wardTitle: wardTitle,
        sessionId: sessionId,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopEnforcement() async {
    try {
      return await FocusPoCChannel.stopMonitoring();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnforcing() async {
    try {
      return await FocusPoCChannel.isServiceRunning();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async {
    try {
      final map = await FocusPoCChannel.getEnforcementStatus();
      return FocusEnforcementStatus.fromMap(map);
    } catch (_) {
      return FocusEnforcementStatus.stopped();
    }
  }
}
