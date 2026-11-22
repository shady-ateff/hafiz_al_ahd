import 'package:flutter/services.dart';
import '../../domain/entities/installed_app_info.dart';
import '../../domain/ports/focus_app_exemption_port.dart';

class NativeFocusAppExemptionPort implements FocusAppExemptionPort {
  static const MethodChannel _channel =
      MethodChannel('com.shadyatef.hafiz_alahd/focus_poc');

  final MethodChannel channel;

  NativeFocusAppExemptionPort({MethodChannel? customChannel})
      : channel = customChannel ?? _channel;

  @override
  Future<List<InstalledAppInfo>> getInstalledApps() async {
    try {
      final List<dynamic>? rawList =
          await channel.invokeListMethod<dynamic>('getInstalledApps');

      if (rawList == null) return [];

      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return InstalledAppInfo(
          packageName: map['packageName'] as String? ?? '',
          appName: map['appName'] as String? ?? '',
          isSystemApp: map['isSystemApp'] as bool? ?? false,
          isSystemCritical: map['isSystemCritical'] as bool? ?? false,
          isExempt: map['isExempt'] as bool? ?? false,
          iconBase64: map['iconBase64'] as String?,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  @override
  Future<bool> syncExemptionsToNative(List<String> exemptPackages) async {
    try {
      final result = await channel.invokeMethod<bool>('setExemptions', {
        'exemptPackages': exemptPackages,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<String>> getSystemCriticalPackages() async {
    try {
      final List<dynamic>? rawList =
          await channel.invokeListMethod<dynamic>('getSystemCriticalPackages');
      if (rawList == null) return [];
      return rawList.map((e) => e.toString()).toList();
    } on PlatformException {
      return [];
    }
  }
}
