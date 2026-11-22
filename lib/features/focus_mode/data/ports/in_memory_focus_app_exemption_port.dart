import '../../domain/entities/installed_app_info.dart';
import '../../domain/ports/focus_app_exemption_port.dart';

/// In-memory mock for [FocusAppExemptionPort] for testing.
class InMemoryFocusAppExemptionPort implements FocusAppExemptionPort {
  List<InstalledAppInfo> apps = [];
  List<String> systemCriticals = [
    'com.android.dialer',
    'com.android.launcher',
    'com.shadyatef.hafiz_alahd',
  ];
  List<String> syncedExemptions = [];

  @override
  Future<List<InstalledAppInfo>> getInstalledApps() async {
    return List.from(apps);
  }

  @override
  Future<bool> syncExemptionsToNative(List<String> exemptPackages) async {
    syncedExemptions = List.from(exemptPackages);
    return true;
  }

  @override
  Future<List<String>> getSystemCriticalPackages() async {
    return List.from(systemCriticals);
  }
}
