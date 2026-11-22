import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/app_exemption_policy.dart';

void main() {
  late AppExemptionPolicy policy;

  setUp(() {
    policy = const AppExemptionPolicy(
      ownPackageName: 'com.shadyatef.hafiz_alahd',
      systemCriticalPackages: {
        'com.android.dialer',
        'com.google.android.apps.nexuslauncher',
      },
    );
  });

  group('AppExemptionPolicy — System Critical & Exemption Rules', () {
    test('Hafiz Al-Ahd is always allowed regardless of user allowlist', () {
      final allowed = policy.isPackageAllowed(
        packageName: 'com.shadyatef.hafiz_alahd',
        userExemptPackages: {},
      );

      expect(allowed, isTrue);
    });

    test('System critical dialer and launcher are always allowed', () {
      expect(
        policy.isPackageAllowed(
          packageName: 'com.android.dialer',
          userExemptPackages: {},
        ),
        isTrue,
      );

      expect(
        policy.isPackageAllowed(
          packageName: 'com.google.android.apps.nexuslauncher',
          userExemptPackages: {},
        ),
        isTrue,
      );
    });

    test('Known emergency packages are always allowed', () {
      expect(
        policy.isPackageAllowed(
          packageName: 'com.android.incallui',
          userExemptPackages: {},
        ),
        isTrue,
      );

      expect(
        policy.isPackageAllowed(
          packageName: 'com.samsung.android.incallui',
          userExemptPackages: {},
        ),
        isTrue,
      );
    });

    test('User-exempted applications are allowed', () {
      final userExempt = {'com.google.android.calculator', 'com.example.notes'};

      expect(
        policy.isPackageAllowed(
          packageName: 'com.google.android.calculator',
          userExemptPackages: userExempt,
        ),
        isTrue,
      );

      expect(
        policy.isPackageAllowed(
          packageName: 'com.example.notes',
          userExemptPackages: userExempt,
        ),
        isTrue,
      );
    });

    test('Distracting non-exempt apps are strictly rejected (blocked)', () {
      final userExempt = {'com.google.android.calculator'};

      expect(
        policy.isPackageAllowed(
          packageName: 'com.facebook.katana',
          userExemptPackages: userExempt,
        ),
        isFalse,
      );

      expect(
        policy.isPackageAllowed(
          packageName: 'com.instagram.android',
          userExemptPackages: userExempt,
        ),
        isFalse,
      );

      expect(
        policy.isPackageAllowed(
          packageName: 'com.google.android.youtube',
          userExemptPackages: userExempt,
        ),
        isFalse,
      );
    });

    test('Null or empty package name returns false', () {
      expect(
        policy.isPackageAllowed(
          packageName: null,
          userExemptPackages: {'com.google.android.calculator'},
        ),
        isFalse,
      );

      expect(
        policy.isPackageAllowed(
          packageName: '   ',
          userExemptPackages: {'com.google.android.calculator'},
        ),
        isFalse,
      );
    });

    test('isSystemCritical correctly identifies critical packages', () {
      expect(policy.isSystemCritical('com.shadyatef.hafiz_alahd'), isTrue);
      expect(policy.isSystemCritical('com.android.dialer'), isTrue);
      expect(policy.isSystemCritical('com.android.incallui'), isTrue);
      expect(policy.isSystemCritical('com.facebook.katana'), isFalse);
    });
  });
}
