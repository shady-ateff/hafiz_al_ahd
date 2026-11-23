import '../entities/installed_app_info.dart';

/// Abstract port for querying installed apps and syncing exemptions with the native shield engine.
abstract class FocusAppExemptionPort {
  /// Queries installed launchable applications from the Android system.
  Future<List<InstalledAppInfo>> getInstalledApps();

  /// Pushes the set of exempt package names to the native Android shield poller.
  Future<bool> syncExemptionsToNative(List<String> exemptPackages);

  /// Retrieves the system critical packages detected on this device (Dialer, Launcher).
  Future<List<String>> getSystemCriticalPackages();
}
