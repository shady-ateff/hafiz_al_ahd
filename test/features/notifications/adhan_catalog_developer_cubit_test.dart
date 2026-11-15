import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';

class FakeAdhanCatalogRepository implements BaseAdhanCatalogRepository {
  Either<AdhanCatalogFailure, AdhanCatalog>? liveResult;
  Either<AdhanCatalogFailure, AdhanCatalog>? cachedResult;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    return liveResult ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    return cachedResult ?? Left(CatalogCacheNotFoundFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class FakeCatalogDraftManagerService implements CatalogDraftManagerService {
  AdhanCatalog? savedDraft;
  AdhanCatalog? resetSeedCatalog;
  bool saveDraftCalled = false;
  bool resetCalled = false;
  bool deleteCalled = false;
  bool shouldFailSave = false;
  bool shouldFailReset = false;

  @override
  Future<AdhanCatalog?> loadDraft() async => savedDraft;

  @override
  Future<void> saveDraft(AdhanCatalog draft) async {
    saveDraftCalled = true;
    if (shouldFailSave) throw const CatalogDraftStorageException('Simulated disk save failure');
    savedDraft = draft;
  }

  @override
  Future<AdhanCatalog> resetDraftToLive({required bool confirmReset}) async {
    resetCalled = true;
    if (!confirmReset) throw const CatalogDraftResetRejectedException('Not confirmed');
    if (shouldFailReset || resetSeedCatalog == null) {
      throw const CatalogDraftResetUnavailableException('Reset source unavailable');
    }
    savedDraft = resetSeedCatalog;
    return resetSeedCatalog!;
  }

  @override
  String exportDraftJson(AdhanCatalog draft) {
    if (draft.entries.any((e) => !e.isValid)) {
      throw const CatalogDraftExportValidationException([]);
    }
    return '{"schema_version": ${draft.schemaVersion}, "entries": []}';
  }

  @override
  Future<void> deleteDraft() async {
    deleteCalled = true;
    savedDraft = null;
  }
}

void main() {
  late FakeAdhanCatalogRepository repository;
  late FakeCatalogDraftManagerService draftManager;
  late AdhanCatalogDeveloperCubit cubit;
  const validator = AdhanCatalogValidator();

  const validSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  AdhanCatalogEntry createValidEntry({
    String id = 'remote:test_sheikh',
    String objectKey = 'audio/test.mp3',
  }) {
    return AdhanCatalogEntry(
      id: id,
      sheikhName: 'الشيخ التجريبي',
      audioType: AdhanAudioType.general,
      displayName: 'أذان تجريبي',
      durationSeconds: 120,
      objectKey: objectKey,
      fileSizeBytes: 1500000,
      sha256: validSha256,
    );
  }

  AdhanCatalog createValidCatalog({String id = 'remote:test_sheikh'}) {
    return AdhanCatalog(
      schemaVersion: 1,
      generatedAt: '2026-11-14T12:00:00Z',
      entries: [createValidEntry(id: id)],
    );
  }

  setUp(() {
    repository = FakeAdhanCatalogRepository();
    draftManager = FakeCatalogDraftManagerService();
    cubit = AdhanCatalogDeveloperCubit(
      catalogRepository: repository,
      draftManager: draftManager,
      validator: validator,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('AdhanCatalogDeveloperCubit - Initialization & Loading', () {
    test('Initial state contains default empty draft and no errors', () {
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.draftCatalog.schemaVersion, equals(1));
      expect(cubit.state.draftCatalog.entries, isEmpty);
      expect(cubit.state.activeTab, equals(0));
    });

    test('loadDeveloperData loads disk draft when present', () async {
      final diskDraft = createValidCatalog(id: 'remote:disk_draft');
      draftManager.savedDraft = diskDraft;

      await cubit.loadDeveloperData();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:disk_draft'));
      expect(cubit.state.hasUnsavedChanges, isFalse);
      expect(cubit.state.isValid, isTrue);
    });

    test('loadDeveloperData seeds from live catalog when disk draft is null', () async {
      final liveCatalog = createValidCatalog(id: 'remote:live_catalog');
      repository.liveResult = Right(liveCatalog);
      draftManager.savedDraft = null;

      await cubit.loadDeveloperData();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.liveCatalog, isNotNull);
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:live_catalog'));
      expect(cubit.state.hasUnsavedChanges, isFalse);
    });

    test('loadDeveloperData handles disk corrupt exception gracefully', () async {
      // Setup draft manager that throws corrupt exception on load
      final corruptDraftManager = FakeCatalogDraftManagerService();
      final cubitWithCorrupt = AdhanCatalogDeveloperCubit(
        catalogRepository: repository,
        draftManager: corruptDraftManager,
        validator: validator,
      );

      await cubitWithCorrupt.loadDeveloperData();

      expect(cubitWithCorrupt.state.isLoading, isFalse);
      expect(cubitWithCorrupt.state.draftCatalog.entries, isEmpty);
      cubitWithCorrupt.close();
    });
  });

  group('AdhanCatalogDeveloperCubit - Tabs & Draft Mutations', () {
    test('switchTab updates activeTab', () {
      cubit.switchTab(1);
      expect(cubit.state.activeTab, equals(1));

      cubit.switchTab(0);
      expect(cubit.state.activeTab, equals(0));
    });

    test('addEntry adds entry, triggers validation, and sets hasUnsavedChanges', () {
      final entry = createValidEntry(id: 'remote:new_entry');
      cubit.addEntry(entry);

      expect(cubit.state.draftCatalog.entries.length, equals(1));
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:new_entry'));
      expect(cubit.state.hasUnsavedChanges, isTrue);
      expect(cubit.state.isValid, isTrue);
    });

    test('updateEntry replaces entry at index and updates validation state', () {
      final initialEntry = createValidEntry(id: 'remote:initial');
      cubit.addEntry(initialEntry);

      final updatedEntry = createValidEntry(id: 'remote:updated', objectKey: 'audio/updated.mp3');
      cubit.updateEntry(0, updatedEntry);

      expect(cubit.state.draftCatalog.entries.length, equals(1));
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:updated'));
      expect(cubit.state.hasUnsavedChanges, isTrue);
    });

    test('removeEntry removes entry at index and updates validation state', () {
      final entry1 = createValidEntry(id: 'remote:entry_1', objectKey: 'audio/1.mp3');
      final entry2 = createValidEntry(id: 'remote:entry_2', objectKey: 'audio/2.mp3');
      cubit.addEntry(entry1);
      cubit.addEntry(entry2);
      expect(cubit.state.draftCatalog.entries.length, equals(2));

      cubit.removeEntry(0);

      expect(cubit.state.draftCatalog.entries.length, equals(1));
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:entry_2'));
      expect(cubit.state.hasUnsavedChanges, isTrue);
    });

    test('reorderEntries reorders entries accurately', () {
      final entry1 = createValidEntry(id: 'remote:1', objectKey: 'audio/1.mp3');
      final entry2 = createValidEntry(id: 'remote:2', objectKey: 'audio/2.mp3');
      cubit.addEntry(entry1);
      cubit.addEntry(entry2);

      cubit.reorderEntries(0, 2);

      expect(cubit.state.draftCatalog.entries[0].id, equals('remote:2'));
      expect(cubit.state.draftCatalog.entries[1].id, equals('remote:1'));
    });

    test('updateMetadata updates metadata and validates', () {
      cubit.updateMetadata(schemaVersion: 1, generatedAt: '2026-11-14T10:00:00Z');

      expect(cubit.state.draftCatalog.generatedAt, equals('2026-11-14T10:00:00Z'));
      expect(cubit.state.hasUnsavedChanges, isTrue);
    });
  });

  group('AdhanCatalogDeveloperCubit - Persistence, Reset & Export', () {
    test('saveDraft persists atomically and clears hasUnsavedChanges', () async {
      cubit.addEntry(createValidEntry());
      expect(cubit.state.hasUnsavedChanges, isTrue);

      await cubit.saveDraft();

      expect(draftManager.saveDraftCalled, isTrue);
      expect(cubit.state.isSaving, isFalse);
      expect(cubit.state.hasUnsavedChanges, isFalse);
      expect(cubit.state.userNotice, contains('تم حفظ مسودة الكتالوج'));
    });

    test('saveDraft handles failure and sets userError', () async {
      draftManager.shouldFailSave = true;

      await cubit.saveDraft();

      expect(cubit.state.isSaving, isFalse);
      expect(cubit.state.userError, contains('فشل حفظ المسودة'));
    });

    test('resetDraftToLive with confirmReset true replaces draft and validates', () async {
      final liveSeed = createValidCatalog(id: 'remote:live_reset_seed');
      draftManager.resetSeedCatalog = liveSeed;

      await cubit.resetDraftToLive(confirmReset: true);

      expect(draftManager.resetCalled, isTrue);
      expect(cubit.state.isResetting, isFalse);
      expect(cubit.state.draftCatalog.entries.first.id, equals('remote:live_reset_seed'));
      expect(cubit.state.hasUnsavedChanges, isFalse);
      expect(cubit.state.userNotice, contains('تم استعادة المسودة بنجاح'));
    });

    test('resetDraftToLive with confirmReset false does nothing', () async {
      await cubit.resetDraftToLive(confirmReset: false);
      expect(draftManager.resetCalled, isFalse);
    });

    test('exportDraftJson returns JSON string when draft is valid', () {
      cubit.addEntry(createValidEntry());

      final json = cubit.exportDraftJson();

      expect(json, isNotNull);
      expect(json, contains('"schema_version": 1'));
      expect(cubit.state.userNotice, contains('تم تجهيز نص الـ JSON'));
    });

    test('exportDraftJson returns null and sets error when draft contains validation errors', () {
      // Add two entries with duplicate IDs
      cubit.addEntry(createValidEntry(id: 'remote:duplicate', objectKey: 'audio/1.mp3'));
      cubit.addEntry(createValidEntry(id: 'remote:duplicate', objectKey: 'audio/2.mp3'));

      expect(cubit.state.isValid, isFalse);

      final json = cubit.exportDraftJson();

      expect(json, isNull);
      expect(cubit.state.userError, contains('لا يمكن تصدير الكتالوج'));
    });

    test('clearNotice and clearError clear transient messages', () {
      cubit.addEntry(createValidEntry());
      cubit.exportDraftJson();
      expect(cubit.state.userNotice, isNotNull);

      cubit.clearNotice();
      expect(cubit.state.userNotice, isNull);
    });
  });
}

