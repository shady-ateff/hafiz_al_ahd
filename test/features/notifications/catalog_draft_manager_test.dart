import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/data/services/catalog_draft_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:path/path.dart' as p;

class FakeAdhanCatalogRepository implements BaseAdhanCatalogRepository {
  Either<AdhanCatalogFailure, AdhanCatalog>? liveResult;
  Either<AdhanCatalogFailure, AdhanCatalog>? cachedResult;
  bool clearCacheCalled = false;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    return liveResult ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    return cachedResult ?? Left(CatalogCacheNotFoundFailure());
  }

  @override
  Future<void> clearCache() async {
    clearCacheCalled = true;
  }
}

void main() {
  late Directory tempDir;
  late FakeAdhanCatalogRepository repository;
  late CatalogDraftManagerServiceImpl draftManager;
  const validator = AdhanCatalogValidator();

  const validSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  AdhanCatalog createTestCatalog({
    String id = 'remote:test_sheikh',
    String objectKey = 'audio/test.mp3',
  }) {
    return AdhanCatalog(
      schemaVersion: 1,
      generatedAt: '2026-11-13T12:00:00Z',
      entries: [
        AdhanCatalogEntry(
          id: id,
          sheikhName: 'الشيخ التجريبي',
          audioType: AdhanAudioType.general,
          displayName: 'أذان تجريبي',
          durationSeconds: 120,
          objectKey: objectKey,
          fileSizeBytes: 1500000,
          sha256: validSha256,
        ),
      ],
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('catalog_draft_test_');
    repository = FakeAdhanCatalogRepository();
    draftManager = CatalogDraftManagerServiceImpl(
      storageDirProvider: () async => tempDir,
      catalogRepository: repository,
      validator: validator,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CatalogDraftManagerService - Basic CRUD & Persistence', () {
    test('loadDraft returns null when draft file does not exist', () async {
      final draft = await draftManager.loadDraft();
      expect(draft, isNull);
    });

    test('saveDraft persists draft atomically and loadDraft reads it back accurately', () async {
      final originalCatalog = createTestCatalog();
      await draftManager.saveDraft(originalCatalog);

      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      expect(await draftFile.exists(), isTrue);

      final loadedDraft = await draftManager.loadDraft();
      expect(loadedDraft, isNotNull);
      expect(loadedDraft!.schemaVersion, equals(originalCatalog.schemaVersion));
      expect(loadedDraft.entries.length, equals(originalCatalog.entries.length));
      expect(loadedDraft.entries.first.id, equals(originalCatalog.entries.first.id));
    });

    test('deleteDraft removes both draft file and temporary file if present', () async {
      final originalCatalog = createTestCatalog();
      await draftManager.saveDraft(originalCatalog);

      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      final tempFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftTempFileName));
      await tempFile.writeAsString('temp');

      expect(await draftFile.exists(), isTrue);
      expect(await tempFile.exists(), isTrue);

      await draftManager.deleteDraft();

      expect(await draftFile.exists(), isFalse);
      expect(await tempFile.exists(), isFalse);
    });
  });

  group('CatalogDraftManagerService - Corrupt Draft Protection', () {
    test('loadDraft throws CatalogDraftCorruptException on malformed JSON string', () async {
      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      await draftFile.writeAsString('{ invalid_json: ');

      expect(
        () => draftManager.loadDraft(),
        throwsA(isA<CatalogDraftCorruptException>()),
      );
    });

    test('loadDraft throws CatalogDraftCorruptException on empty file', () async {
      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      await draftFile.writeAsString('   ');

      expect(
        () => draftManager.loadDraft(),
        throwsA(isA<CatalogDraftCorruptException>()),
      );
    });

    test('loadDraft throws CatalogDraftCorruptException when root is not a JSON object', () async {
      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      await draftFile.writeAsString('["item1", "item2"]');

      expect(
        () => draftManager.loadDraft(),
        throwsA(isA<CatalogDraftCorruptException>()),
      );
    });

    test('loadDraft throws CatalogDraftCorruptException when file exceeds max draft size', () async {
      final draftFile = File(p.join(tempDir.path, CatalogDeveloperConfig.draftFileName));
      // Create file larger than 2MB
      final largeBytes = List<int>.filled(CatalogDeveloperConfig.maxDraftSizeBytes + 10, 65);
      await draftFile.writeAsBytes(largeBytes);

      expect(
        () => draftManager.loadDraft(),
        throwsA(isA<CatalogDraftCorruptException>()),
      );
    });
  });

  group('CatalogDraftManagerService - Atomic Persistence Protection', () {
    test('saveDraft cleans up temp file if rename or write encounters failure', () async {
      // Storage dir provider that throws FileSystemException
      final brokenManager = CatalogDraftManagerServiceImpl(
        storageDirProvider: () async => throw const FileSystemException('Disk access denied'),
        catalogRepository: repository,
        validator: validator,
      );

      final catalog = createTestCatalog();
      await expectLater(
        () => brokenManager.saveDraft(catalog),
        throwsA(isA<CatalogDraftStorageException>()),
      );
    });

    test('Existing draft remains intact if atomic save of new draft fails', () async {
      final originalCatalog = createTestCatalog(id: 'remote:initial_draft');
      await draftManager.saveDraft(originalCatalog);

      // Verify original draft is in place
      final loadedInitial = await draftManager.loadDraft();
      expect(loadedInitial?.entries.first.id, equals('remote:initial_draft'));
    });
  });

  group('CatalogDraftManagerService - Reset Safeguards', () {
    test('resetDraftToLive throws CatalogDraftResetRejectedException when confirmReset is false', () async {
      expect(
        () => draftManager.resetDraftToLive(confirmReset: false),
        throwsA(isA<CatalogDraftResetRejectedException>()),
      );
    });

    test('resetDraftToLive replaces draft with live catalog when live fetch succeeds', () async {
      final existingDraft = createTestCatalog(id: 'remote:old_draft');
      await draftManager.saveDraft(existingDraft);

      final liveCatalog = createTestCatalog(id: 'remote:live_sheikh');
      repository.liveResult = Right(liveCatalog);

      final result = await draftManager.resetDraftToLive(confirmReset: true);
      expect(result.entries.first.id, equals('remote:live_sheikh'));

      final currentDraft = await draftManager.loadDraft();
      expect(currentDraft?.entries.first.id, equals('remote:live_sheikh'));
    });

    test('resetDraftToLive falls back to valid cached catalog when live fetch fails', () async {
      final existingDraft = createTestCatalog(id: 'remote:old_draft');
      await draftManager.saveDraft(existingDraft);

      // Live fetch fails
      repository.liveResult = Left(CatalogNetworkFailure());

      // Cached catalog is valid
      final cachedCatalog = createTestCatalog(id: 'remote:cached_sheikh');
      repository.cachedResult = Right(cachedCatalog);

      final result = await draftManager.resetDraftToLive(confirmReset: true);
      expect(result.entries.first.id, equals('remote:cached_sheikh'));

      final currentDraft = await draftManager.loadDraft();
      expect(currentDraft?.entries.first.id, equals('remote:cached_sheikh'));
    });

    test('resetDraftToLive falls back to cache when live catalog is completely corrupt', () async {
      final existingDraft = createTestCatalog(id: 'remote:old_draft');
      await draftManager.saveDraft(existingDraft);

      // Live returns completely corrupt catalog
      final corruptLive = const AdhanCatalog(
        schemaVersion: 1,
        entries: [],
        rawEntriesCount: 3,
        droppedEntriesCount: 3,
      );
      repository.liveResult = Right(corruptLive);

      // Cache is valid
      final cachedCatalog = createTestCatalog(id: 'remote:cached_sheikh');
      repository.cachedResult = Right(cachedCatalog);

      final result = await draftManager.resetDraftToLive(confirmReset: true);
      expect(result.entries.first.id, equals('remote:cached_sheikh'));

      final currentDraft = await draftManager.loadDraft();
      expect(currentDraft?.entries.first.id, equals('remote:cached_sheikh'));
    });

    test('resetDraftToLive throws CatalogDraftResetUnavailableException and leaves current draft untouched when both live and cache fail', () async {
      final existingDraft = createTestCatalog(id: 'remote:preserved_draft');
      await draftManager.saveDraft(existingDraft);

      repository.liveResult = Left(CatalogNetworkFailure());
      repository.cachedResult = Left(CatalogCacheNotFoundFailure());

      await expectLater(
        () => draftManager.resetDraftToLive(confirmReset: true),
        throwsA(isA<CatalogDraftResetUnavailableException>()),
      );

      // Existing draft MUST NOT be deleted or modified
      final currentDraft = await draftManager.loadDraft();
      expect(currentDraft, isNotNull);
      expect(currentDraft!.entries.first.id, equals('remote:preserved_draft'));
    });
  });

  group('CatalogDraftManagerService - Draft Export', () {
    test('exportDraftJson returns formatted indented JSON for valid catalog', () {
      final catalog = createTestCatalog();
      final exportedJson = draftManager.exportDraftJson(catalog);

      expect(exportedJson, contains('"schema_version": 1'));
      expect(exportedJson, contains('"remote:test_sheikh"'));

      // Verify parseable back to Map
      final decoded = jsonDecode(exportedJson) as Map<String, dynamic>;
      expect(decoded['schema_version'], equals(1));
    });

    test('exportDraftJson throws CatalogDraftExportValidationException when draft contains errors', () {
      // Catalog with duplicate entry IDs
      const entry1 = AdhanCatalogEntry(
        id: 'remote:same_id',
        sheikhName: 'الشيخ 1',
        audioType: AdhanAudioType.general,
        displayName: 'أذان 1',
        durationSeconds: 120,
        objectKey: 'audio/1.mp3',
        fileSizeBytes: 1000000,
        sha256: validSha256,
      );
      const entry2 = AdhanCatalogEntry(
        id: 'remote:same_id',
        sheikhName: 'الشيخ 2',
        audioType: AdhanAudioType.fajr,
        displayName: 'أذان 2',
        durationSeconds: 120,
        objectKey: 'audio/2.mp3',
        fileSizeBytes: 1000000,
        sha256: validSha256,
      );

      final invalidCatalog = const AdhanCatalog(
        schemaVersion: 1,
        entries: [entry1, entry2],
      );

      expect(
        () => draftManager.exportDraftJson(invalidCatalog),
        throwsA(isA<CatalogDraftExportValidationException>()),
      );
    });
  });
}
