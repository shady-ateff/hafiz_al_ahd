import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/screens/adhan_catalog_developer_screen.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/widgets/catalog_draft_entry_dialog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';

class MockAdhanCatalogRepository implements BaseAdhanCatalogRepository {
  AdhanCatalog? liveCatalog;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    if (liveCatalog != null) return Right(liveCatalog!);
    return Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    if (liveCatalog != null) return Right(liveCatalog!);
    return Left(CatalogCacheNotFoundFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class MockCatalogDraftManagerService implements CatalogDraftManagerService {
  AdhanCatalog? draft;

  @override
  Future<AdhanCatalog?> loadDraft() async => draft;

  @override
  Future<void> saveDraft(AdhanCatalog draft) async {
    this.draft = draft;
  }

  @override
  Future<AdhanCatalog> resetDraftToLive({required bool confirmReset}) async {
    return draft ?? const AdhanCatalog(schemaVersion: 1, entries: []);
  }

  @override
  String exportDraftJson(AdhanCatalog draft) => '{"schema_version": 1}';

  @override
  Future<void> deleteDraft() async {
    draft = null;
  }
}

void main() {
  late MockAdhanCatalogRepository mockRepo;
  late MockCatalogDraftManagerService mockDraftManager;
  const validator = AdhanCatalogValidator();

  const validSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  final testEntry = const AdhanCatalogEntry(
    id: 'remote:test_sheikh',
    sheikhName: 'الشيخ التجريبي',
    audioType: AdhanAudioType.general,
    displayName: 'أذان تجريبي',
    durationSeconds: 120,
    objectKey: 'audio/test.mp3',
    fileSizeBytes: 1500000,
    sha256: validSha256,
  );

  final testCatalog = AdhanCatalog(
    schemaVersion: 1,
    generatedAt: '2026-11-14T12:00:00Z',
    entries: [testEntry],
  );

  setUp(() async {
    await sl.reset();
    mockRepo = MockAdhanCatalogRepository()..liveCatalog = testCatalog;
    mockDraftManager = MockCatalogDraftManagerService()..draft = testCatalog;

    sl.registerFactory<AdhanCatalogDeveloperCubit>(
      () => AdhanCatalogDeveloperCubit(
        catalogRepository: mockRepo,
        draftManager: mockDraftManager,
        validator: validator,
      ),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget buildTestableWidget() {
    return const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AdhanCatalogDeveloperScreen(),
      ),
    );
  }

  group('AdhanCatalogDeveloperScreen Widget Tests', () {
    testWidgets('Renders AppBar with DEV badge and Arabic title', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('DEV'), findsOneWidget);
      expect(find.text('إدارة كتالوج الأذان'), findsOneWidget);
      expect(find.text('محرر المسودة (Draft)'), findsOneWidget);
      expect(find.text('الكتالوج المباشر (Live)'), findsOneWidget);
    });

    testWidgets('Draft Editor tab renders metadata and entry card', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Check Metadata
      expect(find.text('بيانات المخطط (Schema Metadata)'), findsOneWidget);
      expect(find.text('إصدار المخطط: 1'), findsOneWidget);
      expect(find.text('عدد الأصوات في المسودة: 1'), findsOneWidget);

      // Check Entry Card
      expect(find.text('أذان تجريبي'), findsOneWidget);
      expect(find.text('الشيخ التجريبي'), findsOneWidget);
      expect(find.text('أذان عام'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('Validation panel shows green check container when valid', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        find.textContaining('المسودة صالحة ومطابقة لجميع قواعد المخطط'),
        findsOneWidget,
      );
    });

    testWidgets('Bottom action bar renders Save, Reset, and Export buttons', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('حفظ المسودة'), findsOneWidget);
      expect(find.byIcon(Icons.restore_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
    });

    testWidgets('Tapping Reset button displays confirmation dialog with warning', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.restore_rounded));
      await tester.pumpAndSettle();

      expect(find.text('تأكيد استعادة المسودة'), findsOneWidget);
      expect(find.textContaining('تحذير: سيتم حذف جميع التعديلات المحلية'), findsOneWidget);
      expect(find.text('تأكيد الاستعادة'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('تأكيد استعادة المسودة'), findsNothing);
    });

    testWidgets('Switching to Live Inspector tab renders live catalog details', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('الكتالوج المباشر (Live)'));
      await tester.pumpAndSettle();

      expect(find.text('حالة الكتالوج المباشر'), findsOneWidget);
      expect(find.text('عدد الأصوات المتاحة: 1'), findsOneWidget);
      expect(find.text('أذان تجريبي'), findsOneWidget);
    });

    testWidgets('When developer tools flag is inactive, title has no gesture detector', (tester) async {
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

      // By default in test environment without dart-define, isCatalogDeveloperToolsActive is false
      expect(isCatalogDeveloperToolsActive, isFalse);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('CatalogDraftEntryDialog renders local file hasher button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: CatalogDraftEntryDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('استيراد وحساب البصمة من ملف محلي'), findsOneWidget);
      expect(find.text('اسم الشيخ *'), findsOneWidget);
      expect(find.text('الاسم المعروض *'), findsOneWidget);
    });
  });
}
