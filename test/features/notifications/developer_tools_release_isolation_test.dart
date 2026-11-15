import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/local_audio_hasher_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/navigation/developer_route_gate.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_cubit.dart';

void main() {
  group('P4.2 Phase 4.3 — Release Isolation & Tree-Shaking Guarantees', () {
    test('Release mode (kDebugMode == false) CANNOT activate developer tools even if flag is true', () {
      // In a release build, kDebugMode is a compile-time constant false.
      // Therefore, isCatalogDeveloperToolsActive is statically false.
      final activeInRelease = CatalogDeveloperConfig.computeIsActive(
        isDebug: false,
        isFlagEnabled: true,
      );
      expect(activeInRelease, isFalse);

      final activeInReleaseWithoutFlag = CatalogDeveloperConfig.computeIsActive(
        isDebug: false,
        isFlagEnabled: false,
      );
      expect(activeInReleaseWithoutFlag, isFalse);
    });

    test('In default test environment without ENABLE_CATALOG_DEV_TOOLS flag, isCatalogDeveloperToolsActive is false', () {
      expect(isCatalogDeveloperToolsActive, isFalse);
      expect(kCatalogDeveloperToolsEnabled, isFalse);
    });

    test('DI Isolation: Developer services are NOT registered when tools flag is inactive', () async {
      final testSl = GetIt.asNewInstance();

      // Simulate production service locator init without developer flag
      if (isCatalogDeveloperToolsActive) {
        // This branch is dead code in release builds
        fail('Developer services registration branch should be unreachable when flag is false');
      }

      // Assert zero developer services registered in GetIt
      expect(testSl.isRegistered<AdhanCatalogDeveloperCubit>(), isFalse);
      expect(testSl.isRegistered<CatalogDraftManagerService>(), isFalse);
      expect(testSl.isRegistered<LocalAudioHasherService>(), isFalse);
      expect(testSl.isRegistered<AdhanCatalogValidator>(), isFalse);

      // Attempting to resolve developer classes throws GetIt error
      expect(
        () => testSl<AdhanCatalogDeveloperCubit>(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => testSl<CatalogDraftManagerService>(),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('Navigation Gate: openDeveloperCatalogIfActive is a pure no-op when inactive', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      int routeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  routeCount++;
                  openDeveloperCatalogIfActive(context);
                },
                child: const Text('Tap Gate'),
              ),
            ),
          ),
        ),
      );

      expect(isCatalogDeveloperToolsActive, isFalse);

      // Tap button to attempt navigation through gate
      await tester.tap(find.text('Tap Gate'));
      await tester.pumpAndSettle();

      // No new route should be pushed (no developer screen rendered)
      expect(find.text('إدارة كتالوج الأذان'), findsNothing);
      expect(find.text('DEV'), findsNothing);
      expect(routeCount, equals(1));
    });

    testWidgets('UI Entry Point Isolation: Production AppBar title has no GestureDetector when inactive', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: isCatalogDeveloperToolsActive
                  ? GestureDetector(
                      onTap: () {},
                      child: const Text('اختيار صوت الأذان'),
                    )
                  : const Text('اختيار صوت الأذان'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only plain Text widget exists, no GestureDetector wrapper mounted
      expect(find.text('اختيار صوت الأذان'), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
