import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/features/home/domain/entities/location_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/base_location_repository.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/save_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockLocationRepo implements BaseLocationRepository {
  @override
  Future<Either<Failure, LocationEntity>> getCachedLocation() async {
    return Right(LocationEntity(
      city: 'Cairo',
      country: 'Egypt',
      latitude: 30.0444,
      longitude: 31.2357,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'isIqamaEnabled': true,
      'dst_offset_minutes': 0,
      'adhan_volume': 1.0,
      'isAdhanVibrationEnabled': true,
      'isAzkarReminderEnabled': true,
      'calculation_method': 'auto',
      'madhab': 'shafi',
      'adhanStyle': 'alarm',
    });
    final prefs = await SharedPreferences.getInstance();

    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerSingleton<SharedPreferences>(prefs);
    }
    if (!sl.isRegistered<GetIqamaDelaysUseCase>()) {
      sl.registerSingleton<GetIqamaDelaysUseCase>(GetIqamaDelaysUseCase());
    }
    if (!sl.isRegistered<SaveIqamaDelaysUseCase>()) {
      sl.registerSingleton<SaveIqamaDelaysUseCase>(SaveIqamaDelaysUseCase());
    }
    if (!sl.isRegistered<GetCachedLocationUseCase>()) {
      sl.registerSingleton<GetCachedLocationUseCase>(
        GetCachedLocationUseCase(MockLocationRepo()),
      );
    }
  });

  Widget buildSettingsApp() {
    return BlocProvider<ThemeCubit>(
      create: (_) => ThemeCubit(),
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  group('Phase P2-C.4: Paint, Layout & Repaint Propagation Audit', () {
    testWidgets('1. Check Repaint Boundaries and Layer allocation in Settings tree', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      final renderView = tester.binding.renderViews.first;

      int totalRenderObjects = 0;
      int repaintBoundaries = 0;
      final List<String> boundaryTypes = [];

      void inspectNode(RenderObject ro) {
        totalRenderObjects++;
        if (ro.isRepaintBoundary) {
          repaintBoundaries++;
          boundaryTypes.add(ro.runtimeType.toString());
        }
        ro.visitChildren(inspectNode);
      }

      renderView.visitChildren(inspectNode);

      debugPrint('═══════════════════════════════════════════════════════════════');
      debugPrint('[P2-C.4 Diagnostic] LAYER BOUNDARIES & REPAINT PROPAGATION:');
      debugPrint('  • Total RenderObjects: $totalRenderObjects');
      debugPrint('  • Total RepaintBoundary nodes: $repaintBoundaries');
      debugPrint('  • Types: $boundaryTypes');
      debugPrint('═══════════════════════════════════════════════════════════════');
    });

    testWidgets('2. Layout vs Paint execution during continuous scroll', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);

      final renderView = tester.binding.renderViews.first;

      // Track needsLayout and needsPaint flags before and after scroll
      int needsLayoutCount = 0;
      int needsPaintCount = 0;

      void checkDirtyFlags(RenderObject ro) {
        if (ro.debugNeedsLayout) needsLayoutCount++;
        if (ro.debugNeedsPaint) needsPaintCount++;
        ro.visitChildren(checkDirtyFlags);
      }

      // Drag by 50px
      final gesture = await tester.startGesture(tester.getCenter(scrollable));
      await gesture.moveBy(const Offset(0, -50));
      
      // Check flags before pump
      renderView.visitChildren(checkDirtyFlags);

      debugPrint('═══════════════════════════════════════════════════════════════');
      debugPrint('[P2-C.4 Diagnostic] DIRTY FLAGS UPON SCROLL DELTA (BEFORE PUMP):');
      debugPrint('  • RenderObjects with debugNeedsLayout: $needsLayoutCount');
      debugPrint('  • RenderObjects with debugNeedsPaint: $needsPaintCount');
      debugPrint('═══════════════════════════════════════════════════════════════');

      expect(needsLayoutCount, equals(0), reason: 'Scroll offset changes should NOT mark any RenderObject for layout');

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

