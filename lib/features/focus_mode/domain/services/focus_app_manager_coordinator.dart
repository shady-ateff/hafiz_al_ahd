import '../entities/installed_app_info.dart';
import '../ports/focus_app_exemption_port.dart';
import '../repositories/focus_app_exemption_repository.dart';
import 'app_exemption_policy.dart';

/// Coordinates app query, exemption state persistence, and native engine synchronization.
class FocusAppManagerCoordinator {
  final FocusAppExemptionPort _port;
  final FocusAppExemptionRepository _repository;
  final AppExemptionPolicy _policy;

  FocusAppManagerCoordinator({
    required FocusAppExemptionPort port,
    required FocusAppExemptionRepository repository,
    AppExemptionPolicy? policy,
  })  : _port = port,
        _repository = repository,
        _policy = policy ?? const AppExemptionPolicy();

  /// Retrieves all launchable installed apps on the device merged with persisted user exemptions.
  Future<List<InstalledAppInfo>> getAppsWithExemptions() async {
    final installedApps = await _port.getInstalledApps();
    final savedExemptions = await _repository.getAllSavedExemptions();
    final systemCriticals = (await _port.getSystemCriticalPackages()).toSet();

    final savedMap = {for (final app in savedExemptions) app.packageName: app};

    final mergedList = <InstalledAppInfo>[];

    for (final app in installedApps) {
      final isCritical = _policy.isSystemCritical(app.packageName) ||
          systemCriticals.contains(app.packageName);

      final saved = savedMap[app.packageName];
      final isExempt = isCritical || (saved?.isExempt ?? false);

      mergedList.add(app.copyWith(
        isSystemCritical: isCritical,
        isExempt: isExempt,
      ));
    }

    // Sort alphabetically by app name
    mergedList.sort((a, b) =>
        a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    return mergedList;
  }

  /// Toggles the exemption status of an application.
  /// Throws [UnsupportedError] if attempting to modify a system-critical app.
  Future<bool> toggleAppExemption(String packageName, bool isExempt,
      {String? appName}) async {
    final systemCriticals = (await _port.getSystemCriticalPackages()).toSet();
    if (_policy.isSystemCritical(packageName) ||
        systemCriticals.contains(packageName)) {
      throw UnsupportedError(
          'Cannot modify exemption status for system critical package: $packageName');
    }

    await _repository.setAppExemption(
      packageName: packageName,
      isExempt: isExempt,
      appName: appName,
      isSystemCritical: false,
    );

    await syncAllExemptionsToNative();
    return true;
  }

  /// Synchronizes the complete set of exempt packages (user exemptions + system criticals)
  /// with the native Android shield poller.
  Future<bool> syncAllExemptionsToNative() async {
    final userExemptions = await _repository.getExemptPackageNames();
    final systemCriticals = await _port.getSystemCriticalPackages();

    final allExempt = <String>{
      _policy.ownPackageName,
      ...AppExemptionPolicy.knownEmergencyPackages,
      ...systemCriticals,
      ...userExemptions,
    }.toList();

    return await _port.syncExemptionsToNative(allExempt);
  }
}
