import 'package:equatable/equatable.dart';

/// Represents an installed application on the user's device with exemption details.
class InstalledAppInfo extends Equatable {
  final String packageName;
  final String appName;
  final bool isSystemApp;
  final bool isSystemCritical;
  final bool isExempt;
  final String? iconBase64;

  const InstalledAppInfo({
    required this.packageName,
    required this.appName,
    this.isSystemApp = false,
    this.isSystemCritical = false,
    this.isExempt = false,
    this.iconBase64,
  });

  InstalledAppInfo copyWith({
    String? packageName,
    String? appName,
    bool? isSystemApp,
    bool? isSystemCritical,
    bool? isExempt,
    String? iconBase64,
  }) {
    return InstalledAppInfo(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      isSystemCritical: isSystemCritical ?? this.isSystemCritical,
      isExempt: isExempt ?? this.isExempt,
      iconBase64: iconBase64 ?? this.iconBase64,
    );
  }

  @override
  List<Object?> get props => [
        packageName,
        appName,
        isSystemApp,
        isSystemCritical,
        isExempt,
        iconBase64,
      ];
}
