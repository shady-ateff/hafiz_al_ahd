import '../entities/installed_app_info.dart';

/// Repository contract for persistent storage of user app exemption preferences.
abstract class FocusAppExemptionRepository {
  /// Saves or updates a list of app exemption records in SQLite.
  Future<void> saveExemptions(List<InstalledAppInfo> apps);

  /// Retrieves all saved exemption records from SQLite.
  Future<List<InstalledAppInfo>> getAllSavedExemptions();

  /// Retrieves only the package names marked as exempt.
  Future<Set<String>> getExemptPackageNames();

  /// Updates the exemption status of a specific package.
  Future<void> setAppExemption({
    required String packageName,
    required bool isExempt,
    String? appName,
    bool isSystemCritical = false,
  });

  /// Clears or resets all user exemptions.
  Future<void> clearExemptions();
}
