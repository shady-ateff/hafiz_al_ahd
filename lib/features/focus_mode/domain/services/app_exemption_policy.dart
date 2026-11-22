/// Enforces app accessibility rules during active focus sessions.
/// Guarantees that system critical apps (phone dialer, emergency UI, home launcher)
/// and Hafiz Al-Ahd itself can never be shielded.
class AppExemptionPolicy {
  static const String defaultOwnPackage = 'com.shadyatef.hafiz_alahd';

  static const Set<String> knownEmergencyPackages = {
    'com.android.incallui',
    'com.google.android.dialer',
    'com.samsung.android.incallui',
    'com.android.dialer',
    'com.android.phone',
  };

  final String ownPackageName;
  final Set<String> systemCriticalPackages;

  const AppExemptionPolicy({
    this.ownPackageName = defaultOwnPackage,
    this.systemCriticalPackages = const {},
  });

  /// Evaluates whether [packageName] is allowed to run without triggering the shield.
  bool isPackageAllowed({
    required String? packageName,
    required Set<String> userExemptPackages,
  }) {
    // Empty or null package: conservative decision (not allowed if foreground is obscure)
    if (packageName == null || packageName.trim().isEmpty) {
      return false;
    }

    final trimmed = packageName.trim();

    // 1. Invariant: Our app is always allowed
    if (trimmed == ownPackageName) {
      return true;
    }

    // 2. Invariant: System critical apps (Dialer, Launcher, Emergency) are always allowed
    if (isSystemCritical(trimmed)) {
      return true;
    }

    // 3. User configured allowlist
    if (userExemptPackages.contains(trimmed)) {
      return true;
    }

    // 4. Default deny: Distracting or unapproved apps are blocked
    return false;
  }

  /// Checks if a package is classified as an immutable system critical app.
  bool isSystemCritical(String packageName) {
    if (packageName == ownPackageName) return true;
    if (knownEmergencyPackages.contains(packageName)) return true;
    if (systemCriticalPackages.contains(packageName)) return true;
    return false;
  }
}
