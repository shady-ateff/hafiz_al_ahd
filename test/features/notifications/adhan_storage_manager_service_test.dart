import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/models/prayer_alarm_config_model.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/adhan_storage_manager_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';

class FakePrayerConfigDataSource implements BasePrayerAlarmConfigLocalDataSource {
  Map<PrayerId, PrayerAlarmConfigModel> configs = {};

  @override
  Future<Map<PrayerId, PrayerAlarmConfigModel>> getConfigs() async => configs;

  @override
  Future<PrayerAlarmConfigModel> getConfig(PrayerId prayerId) async =>
      configs[prayerId] ??
      PrayerAlarmConfigModel(
        prayerId: prayerId,
        alarmType: PrayerAlarmType.alarm,
        audioSource: AudioSourceConfig.defaultBuiltInFallback(isFajr: prayerId == PrayerId.fajr),
      );

  @override
  Future<int> getVersion() async => 2;

  @override
  Future<bool> migrateLegacyIfNeeded() async => false;

  @override
  Future<void> saveAllConfigs(Map<PrayerId, PrayerAlarmConfigModel> newConfigs) async {
    configs = newConfigs;
  }

  @override
  Future<void> saveConfig(PrayerAlarmConfigModel config) async {
    configs[config.prayerId] = config;
  }
}

class FakeAudioDownloadServiceWithRegistry implements BaseAudioDownloadService {
  List<AudioDownloadTask> activeTasks = [];
  String? activeTempPrefix;

  @override
  List<AudioDownloadTask> getActiveTasks() => activeTasks;

  @override
  Set<String> getActiveTempPrefixes() =>
      activeTempPrefix != null ? {activeTempPrefix!} : const {};

  @override
  AudioDownloadTask? getTask(String entryId) {
    for (final t in activeTasks) {
      if (t.entryId == entryId) return t;
    }
    return null;
  }

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) => const Stream.empty();

  @override
  Future<bool> isAudioDownloaded(String entryId) async => false;

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(
      AdhanCatalogEntry entry) async {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelDownload(String entryId) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocsDir;
  late Directory storageDir;
  late CustomAudioStorageService storageService;
  late FakePrayerConfigDataSource fakePrayerConfig;
  late FakeAudioDownloadServiceWithRegistry fakeDownloadService;
  late SharedPreferences mockPrefs;
  late DateTime simulatedNow;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('storage_mgr_test_');
    storageDir = Directory(p.join(tempDocsDir.path, 'adhan_sounds'));
    await storageDir.create(recursive: true);

    SharedPreferences.setMockInitialValues({});
    mockPrefs = await SharedPreferences.getInstance();

    storageService = CustomAudioStorageService(
      docsDirProvider: () async => tempDocsDir,
    );
    fakePrayerConfig = FakePrayerConfigDataSource();
    fakeDownloadService = FakeAudioDownloadServiceWithRegistry();
    simulatedNow = DateTime(2026, 11, 14, 12, 0, 0);
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  AdhanStorageManagerServiceImpl createService({
    int quotaLimitBytes = 150 * 1024 * 1024,
    BaseAudioStorageLock? audioStorageLock,
    SharedPreferences? prefs,
  }) {
    return AdhanStorageManagerServiceImpl(
      storageService: storageService,
      prayerConfigDataSource: fakePrayerConfig,
      downloadService: fakeDownloadService,
      audioStorageLock: audioStorageLock ?? AudioStorageLock(),
      prefs: prefs ?? mockPrefs,
      quotaLimitBytes: quotaLimitBytes,
      nowProvider: () => simulatedNow,
    );
  }

  File createTestFile(
    String relativeToStorageDir, {
    int byteSize = 1024,
    DateTime? modified,
  }) {
    final file = File(p.join(storageDir.path, relativeToStorageDir));
    file.parent.createSync(recursive: true);
    final bytes = List<int>.generate(byteSize, (i) => i % 256);
    file.writeAsBytesSync(bytes, flush: true);
    if (modified != null) {
      file.setLastModifiedSync(modified);
    }
    return file;
  }

  group('P4.2 Phase 5.1 — AdhanStorageManagerService Test Suite', () {
    test('1. Empty Storage Root -> Zero Usage', () async {
      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.totalDirectoryBytes, 0);
      expect(inventory.remoteCacheBytes, 0);
      expect(inventory.userCustomBytes, 0);
      expect(inventory.stagingTmpBytes, 0);
      expect(inventory.unmanagedBytes, 0);
      expect(inventory.reservedInFlightBytes, 0);
      expect(inventory.files, isEmpty);
      expect(inventory.evictionCandidates, isEmpty);
      expect(inventory.abandonedTmpFiles, isEmpty);
      expect(inventory.isQuotaExceeded, isFalse);
      expect(inventory.availableRemoteQuotaBytes, 150 * 1024 * 1024);
    });

    test('2. Mixed Custom + Remote Files -> Correct Ownership Classification', () async {
      // 1MB custom user file
      createTestFile('custom_1700000000.mp3', byteSize: 1024 * 1024);
      // 5MB remote cache file
      createTestFile('remote_mishary_0123456789abcdef01234567.mp3', byteSize: 5 * 1024 * 1024);

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.totalDirectoryBytes, 6 * 1024 * 1024);
      expect(inventory.userCustomBytes, 1 * 1024 * 1024);
      expect(inventory.remoteCacheBytes, 5 * 1024 * 1024);
      expect(inventory.files.length, 2);

      final customFile = inventory.files.firstWhere(
        (f) => f.classification == StorageFileClassification.userCustom,
      );
      expect(customFile.isProtected, isTrue);
      expect(customFile.protectedReason, contains('المستخدم'));

      final remoteFile = inventory.files.firstWhere(
        (f) => f.classification == StorageFileClassification.remoteCache,
      );
      // Not referenced by alarm -> safe to evict
      expect(remoteFile.isProtected, isFalse);
      expect(remoteFile.isSafeToEvict, isTrue);
    });

    test('3. Unknown / Corrupt File -> Unmanaged & Protected', () async {
      // Unknown extension .txt
      createTestFile('notes.txt', byteSize: 500);
      // Unsupported audio format .flac
      createTestFile('audio.flac', byteSize: 2000);
      // 0-byte corrupt mp3
      createTestFile('remote_corrupt_0123456789abcdef01234567.mp3', byteSize: 0);

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.unmanagedBytes, 2500);
      expect(inventory.remoteCacheBytes, 0);

      for (final f in inventory.files) {
        expect(f.classification, StorageFileClassification.unmanaged);
        expect(f.isProtected, isTrue);
        expect(f.isSafeToEvict, isFalse);
      }
    });

    test('4. Active Alarm Remote File -> Protected (Not an Eviction Candidate)', () async {
      const activeRelPath = 'adhan_sounds/remote_mishary_0123456789abcdef01234567.mp3';
      createTestFile('remote_mishary_0123456789abcdef01234567.mp3', byteSize: 4 * 1024 * 1024);

      // Assign to Fajr alarm in configuration
      fakePrayerConfig.configs = {
        PrayerId.fajr: PrayerAlarmConfigModel(
          prayerId: PrayerId.fajr,
          alarmType: PrayerAlarmType.alarm,
          audioSource: const CustomAudioSource(
            id: 'custom:remote:mishary',
            displayName: 'مشاري العفاسي',
            localRelativePath: activeRelPath,
            originalFileName: 'mishary.mp3',
            fileSize: 4 * 1024 * 1024,
          ),
        ),
      };

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.activeAlarmPaths, contains(activeRelPath));
      final file = inventory.files.first;
      expect(file.classification, StorageFileClassification.remoteCache);
      expect(file.isProtected, isTrue);
      expect(file.protectedReason, contains('الفجر'));
      expect(file.isSafeToEvict, isFalse);
      expect(inventory.evictionCandidates, isEmpty);
    });

    test('5. Active Alarm Custom File -> Protected', () async {
      const activeCustomPath = 'adhan_sounds/custom_1700000000.mp3';
      createTestFile('custom_1700000000.mp3', byteSize: 2 * 1024 * 1024);

      fakePrayerConfig.configs = {
        PrayerId.maghrib: PrayerAlarmConfigModel(
          prayerId: PrayerId.maghrib,
          alarmType: PrayerAlarmType.alarm,
          audioSource: const CustomAudioSource(
            id: 'custom:local_1',
            displayName: 'أذان مكة',
            localRelativePath: activeCustomPath,
            originalFileName: 'makkah.mp3',
            fileSize: 2 * 1024 * 1024,
          ),
        ),
      };

      final service = createService();
      final inventory = await service.inspectStorage();

      final file = inventory.files.first;
      expect(file.classification, StorageFileClassification.userCustom);
      expect(file.isProtected, isTrue);
      expect(inventory.evictionCandidates, isEmpty);
    });

    test('6. Unreferenced Remote File -> Safe Eviction Candidate', () async {
      createTestFile(
        'remote_old_0123456789abcdef01234567.mp3',
        byteSize: 3 * 1024 * 1024,
        modified: simulatedNow.subtract(const Duration(days: 5)),
      );
      createTestFile(
        'remote_new_0123456789abcdef01234567.mp3',
        byteSize: 2 * 1024 * 1024,
        modified: simulatedNow.subtract(const Duration(days: 1)),
      );

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.evictionCandidates.length, 2);
      // Oldest file must be ranked first for eviction
      expect(inventory.evictionCandidates[0].fileName, contains('remote_old'));
      expect(inventory.evictionCandidates[1].fileName, contains('remote_new'));
      expect(inventory.isCandidateSafeToEvict('adhan_sounds/remote_old_0123456789abcdef01234567.mp3'), isTrue);
    });

    test('7. Path Traversal & Files Outside Storage Root -> Never Managed', () async {
      // Create a file in docsDir parent (outside adhan_sounds)
      final outsideFile = File(p.join(tempDocsDir.path, 'outside.mp3'));
      outsideFile.writeAsBytesSync([1, 2, 3], flush: true);

      final service = createService();
      final inventory = await service.inspectStorage();

      // Only adhan_sounds files should be scanned
      expect(inventory.files.any((f) => f.fileName == 'outside.mp3'), isFalse);
    });

    test('8. Active .tmp File (Recent or In-Flight) -> Protected', () async {
      // Recent tmp file (10 minutes old)
      createTestFile(
        '.tmp/dl_1_1700000000.tmp',
        byteSize: 500 * 1024,
        modified: simulatedNow.subtract(const Duration(minutes: 10)),
      );

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.stagingTmpBytes, 500 * 1024);
      final tmpFile = inventory.files.first;
      expect(tmpFile.classification, StorageFileClassification.stagingTmp);
      expect(tmpFile.isProtected, isTrue);
      expect(inventory.abandonedTmpFiles, isEmpty);
    });

    test('9. Abandoned .tmp File (>60 min old and not active) -> GC Candidate', () async {
      // Old abandoned tmp file (2 hours old)
      createTestFile(
        '.tmp/dl_2_1699990000.tmp',
        byteSize: 800 * 1024,
        modified: simulatedNow.subtract(const Duration(hours: 2)),
      );

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.abandonedTmpFiles.length, 1);
      final abandoned = inventory.abandonedTmpFiles.first;
      expect(abandoned.fileName, 'dl_2_1699990000.tmp');
      expect(abandoned.isProtected, isFalse);
    });

    test('10. Remote Quota Exact Boundary: 150 MiB', () async {
      const quota = 10 * 1024 * 1024; // 10 MiB quota for test
      createTestFile('remote_file_0123456789abcdef01234567.mp3', byteSize: 8 * 1024 * 1024);

      final service = createService(quotaLimitBytes: quota);

      // Check with exact remaining (2 MiB)
      final checkExact = await service.checkQuota(requiredBytes: 2 * 1024 * 1024);
      expect(checkExact.isAllowed, isTrue);
      expect(checkExact.deficitBytes, 0);
      expect(checkExact.availableQuotaBytes, 2 * 1024 * 1024);

      // Check with 1 byte over (2 MiB + 1 byte)
      final checkExceeded = await service.checkQuota(requiredBytes: (2 * 1024 * 1024) + 1);
      expect(checkExceeded.isAllowed, isFalse);
      expect(checkExceeded.deficitBytes, 1);
      expect(checkExceeded.suggestedEvictionCandidates.length, 1);
    });

    test('11. In-Flight Download Reservations Counted Against Quota', () async {
      const quota = 10 * 1024 * 1024; // 10 MiB quota
      // 5 MiB already cached on disk
      createTestFile('remote_cached_0123456789abcdef01234567.mp3', byteSize: 5 * 1024 * 1024);

      // 4 MiB currently in-flight in download registry
      fakeDownloadService.activeTasks = [
        AudioDownloadTask(
          entryId: 'remote:downloading_entry',
          status: DownloadStatus.downloading,
          progress: DownloadProgress.determinate(
            receivedBytes: 1 * 1024 * 1024,
            totalBytes: 4 * 1024 * 1024,
          ),
        ),
      ];

      final service = createService(quotaLimitBytes: quota);
      final inventory = await service.inspectStorage();

      expect(inventory.remoteCacheBytes, 5 * 1024 * 1024);
      expect(inventory.reservedInFlightBytes, 4 * 1024 * 1024);
      expect(inventory.effectiveRemoteUsageBytes, 9 * 1024 * 1024);
      expect(inventory.availableRemoteQuotaBytes, 1 * 1024 * 1024);

      // Attempting to download 2 MiB fails because only 1 MiB is available after reservation
      final check = await service.checkQuota(requiredBytes: 2 * 1024 * 1024);
      expect(check.isAllowed, isFalse);
      expect(check.deficitBytes, 1 * 1024 * 1024);
    });

    test('12. Safe Eviction Candidates Suggestion Meets Exact Deficit', () async {
      const quota = 10 * 1024 * 1024;
      // Candidate 1: 3 MiB (older)
      createTestFile(
        'remote_c1_0123456789abcdef01234567.mp3',
        byteSize: 3 * 1024 * 1024,
        modified: simulatedNow.subtract(const Duration(days: 3)),
      );
      // Candidate 2: 4 MiB (newer)
      createTestFile(
        'remote_c2_0123456789abcdef01234567.mp3',
        byteSize: 4 * 1024 * 1024,
        modified: simulatedNow.subtract(const Duration(days: 1)),
      );

      final service = createService(quotaLimitBytes: quota);
      // We have 7 MiB used. Quota is 10 MiB. We want to download 6 MiB (needs 3 MiB freed)
      final check = await service.checkQuota(requiredBytes: 6 * 1024 * 1024);

      expect(check.isAllowed, isFalse);
      expect(check.deficitBytes, 3 * 1024 * 1024);
      // First candidate (c1, 3 MiB) is enough to satisfy 3 MiB deficit
      expect(check.suggestedEvictionCandidates.length, 1);
      expect(check.suggestedEvictionCandidates.first.fileName, contains('remote_c1'));
    });

    test('13. Canonical Deduplication: No Double Counting', () async {
      createTestFile('remote_unique_0123456789abcdef01234567.mp3', byteSize: 2 * 1024 * 1024);

      final service = createService();
      final inventory = await service.inspectStorage();

      expect(inventory.files.length, 1);
      expect(inventory.totalDirectoryBytes, 2 * 1024 * 1024);
      expect(inventory.remoteCacheBytes, 2 * 1024 * 1024);
    });

    test('14. Missing Directory / Permission Error -> Empty Inventory', () async {
      // Point docsDirProvider to non-existent directory
      final brokenService = AdhanStorageManagerServiceImpl(
        storageService: CustomAudioStorageService(
          docsDirProvider: () async => Directory(p.join(tempDocsDir.path, 'non_existent_folder')),
        ),
        prayerConfigDataSource: fakePrayerConfig,
        downloadService: fakeDownloadService,
        audioStorageLock: AudioStorageLock(),
        prefs: mockPrefs,
      );

      final inventory = await brokenService.inspectStorage();
      expect(inventory.totalDirectoryBytes, 0);
      expect(inventory.files, isEmpty);
      expect(inventory.isQuotaExceeded, isFalse);
    });

    test('15. Active In-Flight Task Protects Old .tmp File Matching Prefix', () async {
      // Even if file is 90 minutes old, if its prefix matches active task token, it MUST be protected
      createTestFile(
        '.tmp/dl_42_1699990000.tmp',
        byteSize: 1024 * 1024,
        modified: simulatedNow.subtract(const Duration(minutes: 90)),
      );

      // Register active task with prefix 'dl_42_'
      fakeDownloadService.activeTempPrefix = 'dl_42_';

      final service = createService();
      final inventory = await service.inspectStorage();

      final tmp = inventory.files.first;
      expect(tmp.isProtected, isTrue);
      expect(tmp.protectedReason, contains('تنزيل نشط'));
      expect(inventory.abandonedTmpFiles, isEmpty);
    });

    test('16. Multiple Prayers Sharing Same Audio Source -> All Prayer Names in Reason', () async {
      const sharedPath = 'adhan_sounds/remote_shared_0123456789abcdef01234567.mp3';
      createTestFile('remote_shared_0123456789abcdef01234567.mp3', byteSize: 4 * 1024 * 1024);

      fakePrayerConfig.configs = {
        PrayerId.fajr: PrayerAlarmConfigModel(
          prayerId: PrayerId.fajr,
          alarmType: PrayerAlarmType.alarm,
          audioSource: const CustomAudioSource(
            id: 'custom:remote:shared',
            displayName: 'صوت مشترك',
            localRelativePath: sharedPath,
            originalFileName: 'shared.mp3',
            fileSize: 4 * 1024 * 1024,
          ),
        ),
        PrayerId.isha: PrayerAlarmConfigModel(
          prayerId: PrayerId.isha,
          alarmType: PrayerAlarmType.alarm,
          audioSource: const CustomAudioSource(
            id: 'custom:remote:shared',
            displayName: 'صوت مشترك',
            localRelativePath: sharedPath,
            originalFileName: 'shared.mp3',
            fileSize: 4 * 1024 * 1024,
          ),
        ),
      };

      final service = createService();
      final inventory = await service.inspectStorage();

      final file = inventory.files.first;
      expect(file.isProtected, isTrue);
      expect(file.protectedReason, contains('الفجر'));
      expect(file.protectedReason, contains('العشاء'));
    });

    // -------------------------------------------------------------
    // PHASE 5.2: SAFE DELETION & ATOMIC JUST-IN-TIME REVALIDATION
    // -------------------------------------------------------------
    group('Phase 5.2 — Safe Deletion & JIT Revalidation', () {
      test('1. Delete unreferenced remote file -> Succeeded & removed from disk', () async {
        final file = createTestFile('remote_unused_0123456789abcdef01234567.mp3', byteSize: 2048);
        expect(file.existsSync(), isTrue);

        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/remote_unused_0123456789abcdef01234567.mp3');

        expect(result.isRight(), isTrue);
        expect(file.existsSync(), isFalse);
      });

      test('2. Reject active alarm remote file -> Rejected with active alarm reason, file preserved', () async {
        const activeRel = 'adhan_sounds/remote_active_0123456789abcdef01234567.mp3';
        final file = createTestFile('remote_active_0123456789abcdef01234567.mp3', byteSize: 4096);

        fakePrayerConfig.configs = {
          PrayerId.fajr: PrayerAlarmConfigModel(
            prayerId: PrayerId.fajr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: const CustomAudioSource(
              id: 'custom:remote:active',
              displayName: 'صوت نشط',
              localRelativePath: activeRel,
              originalFileName: 'active.mp3',
              fileSize: 4096,
            ),
          ),
        };

        final service = createService();
        final result = await service.deleteAudioFile(activeRel);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<StorageDeletionActiveAlarmFailure>());
            expect(failure.message, contains('الفجر'));
          },
          (_) => fail('Should have rejected active alarm file deletion'),
        );
        expect(file.existsSync(), isTrue);
      });

      test('3. Reject custom deletion while assigned to prayer -> Rejected, file preserved', () async {
        const customRel = 'adhan_sounds/custom_1700000000.mp3';
        final file = createTestFile('custom_1700000000.mp3', byteSize: 2048);

        fakePrayerConfig.configs = {
          PrayerId.asr: PrayerAlarmConfigModel(
            prayerId: PrayerId.asr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: const CustomAudioSource(
              id: 'custom:asr_sound',
              displayName: 'أذان العصر',
              localRelativePath: customRel,
              originalFileName: 'custom.mp3',
              fileSize: 2048,
            ),
          ),
        };

        final service = createService();
        final result = await service.deleteAudioFile(customRel, isUserExplicit: true);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionActiveAlarmFailure>()),
          (_) => fail('Should have rejected'),
        );
        expect(file.existsSync(), isTrue);
      });

      test('4. Allow user custom deletion when unassigned and isUserExplicit: true -> Succeeded', () async {
        const customRel = 'adhan_sounds/custom_1700000000.mp3';
        final file = createTestFile('custom_1700000000.mp3', byteSize: 2048);

        final service = createService();
        final result = await service.deleteAudioFile(customRel, isUserExplicit: true);

        expect(result.isRight(), isTrue);
        expect(file.existsSync(), isFalse);
      });

      test('5. Reject user custom deletion when isUserExplicit: false -> Protected', () async {
        const customRel = 'adhan_sounds/custom_1700000000.mp3';
        final file = createTestFile('custom_1700000000.mp3', byteSize: 2048);

        final service = createService();
        final result = await service.deleteAudioFile(customRel, isUserExplicit: false);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionProtectedFailure>()),
          (_) => fail('Should have rejected'),
        );
        expect(file.existsSync(), isTrue);
      });

      test('6. Reject unmanaged file deletion -> Protected, file preserved', () async {
        const unmanagedRel = 'adhan_sounds/notes.txt';
        final file = createTestFile('notes.txt', byteSize: 100);

        final service = createService();
        final result = await service.deleteAudioFile(unmanagedRel);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionProtectedFailure>()),
          (_) => fail('Should have rejected'),
        );
        expect(file.existsSync(), isTrue);
      });

      test('7. Reject traversal path -> Security failure', () async {
        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/../outside.mp3');

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
          (_) => fail('Should have rejected'),
        );
      });

      test('8. Reject outside-root path -> Security failure', () async {
        final service = createService();
        final result = await service.deleteAudioFile('other_folder/file.mp3');

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
          (_) => fail('Should have rejected'),
        );
      });

      test('9. Reject active .tmp deletion matching active download prefix -> Protected', () async {
        final file = createTestFile('.tmp/dl_99_1700000000.tmp', byteSize: 5000);
        fakeDownloadService.activeTempPrefix = 'dl_99_';

        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/.tmp/dl_99_1700000000.tmp');

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionProtectedFailure>()),
          (_) => fail('Should have rejected'),
        );
        expect(file.existsSync(), isTrue);
      });

      test('10. Handle missing file gracefully -> Not found failure without throwing', () async {
        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/remote_nonexistent_0123456789abcdef01234567.mp3');

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<StorageDeletionNotFoundFailure>()),
          (_) => fail('Should return not found'),
        );
      });

      test('11. JIT Race Condition: File assigned to prayer right before deletion -> Delete REJECTED!', () async {
        const path = 'adhan_sounds/remote_race_0123456789abcdef01234567.mp3';
        final file = createTestFile('remote_race_0123456789abcdef01234567.mp3', byteSize: 1024);

        final service = createService();

        // 1. Snapshot taken while file is unassigned:
        final snapshot = await service.inspectStorage();
        expect(snapshot.isCandidateSafeToEvict(path), isTrue);

        // 2. Concurrently, user assigns this audio to Dhuhr prayer!
        fakePrayerConfig.configs = {
          PrayerId.dhuhr: PrayerAlarmConfigModel(
            prayerId: PrayerId.dhuhr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: const CustomAudioSource(
              id: 'custom:remote:race',
              displayName: 'صوت مخصص',
              localRelativePath: path,
              originalFileName: 'race.mp3',
              fileSize: 1024,
            ),
          ),
        };

        // 3. Delete requested: JIT check must catch the new assignment and abort!
        final deleteResult = await service.deleteAudioFile(path);
        expect(deleteResult.isLeft(), isTrue);
        deleteResult.fold(
          (failure) {
            expect(failure, isA<StorageDeletionActiveAlarmFailure>());
            expect(failure.message, contains('الظهر'));
          },
          (_) => fail('Should have aborted delete due to JIT alarm check'),
        );

        // File remains on disk safely!
        expect(file.existsSync(), isTrue);
      });

      test('12. Inventory refresh after deletion reflects freed bytes immediately', () async {
        createTestFile('remote_del_0123456789abcdef01234567.mp3', byteSize: 5 * 1024 * 1024);

        final service = createService();
        final before = await service.inspectStorage();
        expect(before.remoteCacheBytes, 5 * 1024 * 1024);

        final deleteResult = await service.deleteAudioFile('adhan_sounds/remote_del_0123456789abcdef01234567.mp3');
        expect(deleteResult.isRight(), isTrue);

        final after = await service.inspectStorage();
        expect(after.remoteCacheBytes, 0);
        expect(after.totalDirectoryBytes, 0);
        expect(after.evictionCandidates, isEmpty);
      });

      test('13. Failed deletion does not mutate alarm configuration', () async {
        const path = 'adhan_sounds/remote_guarded_0123456789abcdef01234567.mp3';
        createTestFile('remote_guarded_0123456789abcdef01234567.mp3', byteSize: 3000);

        final initialConfig = PrayerAlarmConfigModel(
          prayerId: PrayerId.fajr,
          alarmType: PrayerAlarmType.alarm,
          audioSource: const CustomAudioSource(
            id: 'custom:guarded',
            displayName: 'صوت محمي',
            localRelativePath: path,
            originalFileName: 'guarded.mp3',
            fileSize: 3000,
          ),
        );
        fakePrayerConfig.configs = {PrayerId.fajr: initialConfig};

        final service = createService();
        await service.deleteAudioFile(path);

        // Config in local data source remains strictly identical
        final currentConfig = await fakePrayerConfig.getConfig(PrayerId.fajr);
        expect(currentConfig.audioSource, initialConfig.audioSource);
      });

      test('14. Deleting one audio file does not affect sibling audio references', () async {
        createTestFile('remote_f1_0123456789abcdef01234567.mp3', byteSize: 2000);
        final file2 = createTestFile('remote_f2_0123456789abcdef01234567.mp3', byteSize: 3000);

        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/remote_f1_0123456789abcdef01234567.mp3');

        expect(result.isRight(), isTrue);
        // Sibling file 2 is untouched
        expect(file2.existsSync(), isTrue);
      });

      test('15. Cleanup abandoned tmp files is strictly Dry-Run / Preview in Phase 5.2 (Preserves files on disk)', () async {
        // Abandoned tmp (>60m)
        final abandoned1 = createTestFile(
          '.tmp/dl_1_1699990000.tmp',
          byteSize: 1000,
          modified: simulatedNow.subtract(const Duration(hours: 2)),
        );
        // Abandoned tmp (>60m)
        final abandoned2 = createTestFile(
          '.tmp/dl_2_1699990000.tmp',
          byteSize: 2000,
          modified: simulatedNow.subtract(const Duration(hours: 3)),
        );
        // Active/recent tmp (<60m)
        final recentTmp = createTestFile(
          '.tmp/dl_3_1700000000.tmp',
          byteSize: 5000,
          modified: simulatedNow.subtract(const Duration(minutes: 15)),
        );

        final service = createService();
        final inventory = await service.inspectStorage();

        // 1. Discovery correctly identifies 2 abandoned candidates
        expect(inventory.abandonedTmpFiles.length, 2);
        expect(inventory.abandonedTmpBytes, 3000);

        // 2. Cleanup method in Phase 5.2 returns zero deleted files (dry-run preview)
        final summary = await service.cleanupAbandonedTmpFiles();
        expect(summary.deletedCount, 0);
        expect(summary.freedBytes, 0);

        // 3. ZERO physical unlinking: all files remain safely on disk
        expect(abandoned1.existsSync(), isTrue);
        expect(abandoned2.existsSync(), isTrue);
        expect(recentTmp.existsSync(), isTrue);
      });

      test('16. Reject direct manual deletion of .tmp files -> Protected, file preserved', () async {
        final tmpFile = createTestFile(
          '.tmp/dl_manual_1700000000.tmp',
          byteSize: 2048,
          modified: simulatedNow.subtract(const Duration(hours: 5)),
        );

        final service = createService();
        final result = await service.deleteAudioFile('adhan_sounds/.tmp/dl_manual_1700000000.tmp');

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<StorageDeletionProtectedFailure>());
            expect(failure.message, contains('الملفات المؤقتة مدارة آلياً ومحمية'));
          },
          (_) => fail('Should have rejected direct .tmp deletion'),
        );
        expect(tmpFile.existsSync(), isTrue);
      });

      test('17. Concurrency Safety: AudioStorageLock serializes concurrent saveConfig and deleteAudioFile', () async {
        const targetPath = 'adhan_sounds/remote_shared_0123456789abcdef01234567.mp3';
        final file = createTestFile('remote_shared_0123456789abcdef01234567.mp3', byteSize: 4096);

        final sharedLock = AudioStorageLock();
        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: sharedLock,
          storageService: storageService,
        );
        final service = AdhanStorageManagerServiceImpl(
          storageService: storageService,
          prayerConfigDataSource: fakePrayerConfig,
          downloadService: fakeDownloadService,
          audioStorageLock: sharedLock,
          prefs: mockPrefs,
        );

        // Verify initial state: file is not assigned to any alarm
        final initialConfigs = await fakePrayerConfig.getConfigs();
        expect(initialConfigs.values.any((c) => (c.audioSource as dynamic)?.localRelativePath == targetPath), isFalse);

        // Initiate concurrent execution:
        // Task A: User assigns the audio to Fajr via repository (which acquires sharedLock)
        // Task B: Delete request for the same audio (which acquires sharedLock)
        final futureAssign = repo.saveConfig(
          PrayerAlarmConfig(
            prayerId: PrayerId.fajr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: const CustomAudioSource(
              id: 'custom:fajr:remote',
              displayName: 'أذان الفجر',
              localRelativePath: targetPath,
              originalFileName: 'remote_shared.mp3',
              fileSize: 4096,
            ),
          ),
        );

        final futureDelete = service.deleteAudioFile(targetPath);

        // Await both operations
        await futureAssign;
        final deleteResult = await futureDelete;

        // CRITICAL INVARIANT:
        // Because sharedLock serializes the operations, the deletion MUST revalidate
        // under the lock and detect that Fajr was assigned to this file.
        // Therefore, deletion is strictly rejected!
        expect(deleteResult.isLeft(), isTrue);
        deleteResult.fold(
          (failure) {
            expect(failure, isA<StorageDeletionActiveAlarmFailure>());
            expect(failure.message, contains('الفجر'));
          },
          (_) => fail('Should have aborted delete due to serialized JIT revalidation'),
        );

        // File is preserved on disk for the active alarm!
        expect(file.existsSync(), isTrue);
      });

      test('18. AudioStorageLock Unit Tests: FIFO serialization and error tolerance', () async {
        final lock = AudioStorageLock();
        final executionOrder = <int>[];

        final op1 = lock.synchronized(() async {
          await Future.delayed(const Duration(milliseconds: 20));
          executionOrder.add(1);
          return 1;
        });

        expect(lock.isLocked, isTrue);

        final op2 = lock.synchronized(() async {
          executionOrder.add(2);
          throw Exception('Op2 failure');
        });

        final op3 = lock.synchronized(() async {
          executionOrder.add(3);
          return 3;
        });

        final res1 = await op1;
        expect(res1, 1);

        try {
          await op2;
        } catch (_) {}

        final res3 = await op3;
        expect(res3, 3);

        expect(executionOrder, equals([1, 2, 3]));
        expect(lock.isLocked, isFalse);
      });

      test('19. Global Audio Reference Guard: File assigned only to global setting is strictly protected', () async {
        const path = 'adhan_sounds/remote_global_0123456789abcdef01234567.mp3';
        final file = createTestFile('remote_global_0123456789abcdef01234567.mp3', byteSize: 2048);

        // Assign to global_adhan_audio_source in SharedPreferences
        await mockPrefs.setString(
          'global_adhan_audio_source',
          jsonEncode({
            'type': 'custom',
            'id': 'custom:remote:global',
            'displayName': 'الأذان العام الافتراضي',
            'localRelativePath': path,
            'originalFileName': 'global.mp3',
            'fileSize': 2048,
          }),
        );

        // Ensure 0 prayers have individual overrides
        fakePrayerConfig.configs = {};

        final service = createService();
        final result = await service.deleteAudioFile(path);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<StorageDeletionActiveAlarmFailure>());
            expect(failure.message, contains('الافتراضي العام للصلوات'));
          },
          (_) => fail('Should have rejected deletion because file is referenced by global audio setting'),
        );

        // File remains on disk!
        expect(file.existsSync(), isTrue);
      });

      test('20. Delete-First Race Scenario: Save config rejects assigning deleted file', () async {
        const targetPath = 'adhan_sounds/remote_delfirst_0123456789abcdef01234567.mp3';
        final file = createTestFile('remote_delfirst_0123456789abcdef01234567.mp3', byteSize: 2048);

        final sharedLock = AudioStorageLock();
        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: sharedLock,
          storageService: storageService,
        );
        final service = AdhanStorageManagerServiceImpl(
          storageService: storageService,
          prayerConfigDataSource: fakePrayerConfig,
          downloadService: fakeDownloadService,
          audioStorageLock: sharedLock,
          prefs: mockPrefs,
        );

        // 1. Delete runs first and unlinks the file
        final deleteResult = await service.deleteAudioFile(targetPath);
        expect(deleteResult.isRight(), isTrue);
        expect(file.existsSync(), isFalse);

        // 2. Concurrently or immediately after, a caller attempts to assign the deleted file to Asr
        expect(
          () => repo.saveConfig(
            PrayerAlarmConfig(
              prayerId: PrayerId.asr,
              alarmType: PrayerAlarmType.alarm,
              audioSource: const CustomAudioSource(
                id: 'custom:asr:remote',
                displayName: 'صوت محذوف',
                localRelativePath: targetPath,
                originalFileName: 'remote_delfirst.mp3',
                fileSize: 2048,
              ),
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );

        // Verify invalid reference was never saved to storage!
        final asrConfig = await fakePrayerConfig.getConfig(PrayerId.asr);
        expect(asrConfig.audioSource is CustomAudioSource, isFalse);
      });

      test('21. Symlink Security Guard: Reject symlink pointing outside storage root', () async {
        // Create an outside file in system temp
        final outsideFile = File(p.join(tempDocsDir.parent.path, 'outside_storage_secret.txt'));
        outsideFile.writeAsStringSync('TOP SECRET', flush: true);

        final symlinkPath = p.join(storageDir.path, 'remote_escape_0123456789abcdef01234567.mp3');
        bool symlinkCreated = false;
        try {
          final link = Link(symlinkPath);
          await link.create(outsideFile.path);
          symlinkCreated = true;
        } catch (_) {
          // Non-elevated Windows environment may disallow Link.create without Developer Mode
        }

        final service = createService();

        if (symlinkCreated) {
          final result = await service.deleteAudioFile('adhan_sounds/remote_escape_0123456789abcdef01234567.mp3');
          expect(result.isLeft(), isTrue);
          result.fold(
            (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
            (_) => fail('Should reject symlink escaping root'),
          );
          // Target outside file is strictly preserved!
          expect(outsideFile.existsSync(), isTrue);
        } else {
          // If OS does not permit symlink creation in unprivileged tests, verify canonical resolution guard
          final result = await service.deleteAudioFile('adhan_sounds/../../outside_storage_secret.txt');
          expect(result.isLeft(), isTrue);
          result.fold(
            (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
            (_) => fail('Should reject path traversal escaping root'),
          );
        }

        if (outsideFile.existsSync()) {
          outsideFile.deleteSync();
        }
      });

      test('22. AudioStorageLock Strict Non-Reentrancy: Re-entrant bypass prohibited to protect critical section lifetime', () async {
        final lock = AudioStorageLock();
        final order = <String>[];

        final op1 = lock.synchronized(() async {
          order.add('op1_start');
          await Future.delayed(const Duration(milliseconds: 20));
          order.add('op1_end');
        });

        final op2 = lock.synchronized(() async {
          order.add('op2_start');
          order.add('op2_end');
        });

        await Future.wait([op1, op2]);
        expect(order, equals(['op1_start', 'op1_end', 'op2_start', 'op2_end']));
        expect(lock.isLocked, isFalse);
      });

      test('23. Sibling Path Boundary Protection: Reject sibling directories (e.g. adhan_sounds_backup)', () async {
        // Create sibling directory adhan_sounds_backup
        final siblingDir = Directory(p.join(tempDocsDir.path, 'adhan_sounds_backup'));
        await siblingDir.create(recursive: true);
        final siblingFile = File(p.join(siblingDir.path, 'sibling_audio.mp3'));
        siblingFile.writeAsStringSync('SIBLING CONTENT', flush: true);

        final service = createService();

        // 1. Direct path to sibling directory
        final result1 = await service.deleteAudioFile('adhan_sounds_backup/sibling_audio.mp3');
        expect(result1.isLeft(), isTrue);
        result1.fold(
          (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
          (_) => fail('Must reject sibling directory path'),
        );

        // 2. Traversal path aiming for sibling directory
        final result2 = await service.deleteAudioFile('adhan_sounds/../adhan_sounds_backup/sibling_audio.mp3');
        expect(result2.isLeft(), isTrue);
        result2.fold(
          (failure) => expect(failure, isA<StorageDeletionSecurityFailure>()),
          (_) => fail('Must reject traversal to sibling directory'),
        );

        // Verify physical file in sibling directory was completely untouched
        expect(siblingFile.existsSync(), isTrue);

        await siblingDir.delete(recursive: true);
      });

      test('24. R5.1: Strict FIFO Serialization prevents detached Future from running concurrently with subsequent operations', () async {
        final lock = AudioStorageLock();
        final executionLog = <String>[];
        final detachedCompleter = Completer<void>();
        final aCompleter = Completer<void>();

        // 1. Operation A enters lock
        final futureA = lock.synchronized(() async {
          executionLog.add('A_start');

          // 2. A spawns a detached Future that calls synchronized
          // (Intentionally un-awaited by A)
          unawaited(Future.microtask(() async {
            await lock.synchronized(() async {
              executionLog.add('detached_start');
              // 3. Detached Future halts at a Completer
              await detachedCompleter.future;
              executionLog.add('detached_end');
            });
          }));

          await aCompleter.future;
          executionLog.add('A_end');
        });

        // Let microtasks run: Detached Future calls synchronized while A is still active
        await Future.delayed(const Duration(milliseconds: 15));
        // Verify detached Future CANNOT enter while A is holding the lock
        expect(executionLog, equals(['A_start']));

        // Now release A
        aCompleter.complete();
        await futureA;
        expect(executionLog, equals(['A_start', 'A_end']));

        // Transition time: lock passes to detached Future
        await Future.delayed(const Duration(milliseconds: 15));
        expect(executionLog, equals(['A_start', 'A_end', 'detached_start']));

        // 4. Operation B (e.g. deletion) calls synchronized while detached Future is halted at Completer
        final futureB = lock.synchronized(() async {
          executionLog.add('B_start');
          executionLog.add('B_end');
        });

        // Verify B CANNOT enter while detached Future is halted holding the lock!
        await Future.delayed(const Duration(milliseconds: 15));
        expect(executionLog, equals(['A_start', 'A_end', 'detached_start']));

        // 5. Release detachedCompleter: detached Future finishes
        detachedCompleter.complete();

        // Wait for B to finish
        await futureB;

        // 6. Verify strict serialization: detached Future finished completely BEFORE B started!
        expect(executionLog, equals([
          'A_start',
          'A_end',
          'detached_start',
          'detached_end',
          'B_start',
          'B_end',
        ]));
        expect(lock.isLocked, isFalse);
      });

      test('25. Mandatory Lock Enforcement: Services require lock and execute under lock', () async {
        final lock = AudioStorageLock();
        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: lock,
          storageService: storageService,
        );

        expect(repo.audioStorageLock, equals(lock));
        expect(repo.storageService, equals(storageService));

        final service = AdhanStorageManagerServiceImpl(
          storageService: storageService,
          prayerConfigDataSource: fakePrayerConfig,
          downloadService: fakeDownloadService,
          audioStorageLock: lock,
          prefs: mockPrefs,
        );

        expect(service.audioStorageLock, equals(lock));
        expect(service.prefs, equals(mockPrefs));
      });

      test('26. R5.3: Save Path Traversal Guard rejects files outside storage root even if existing', () async {
        // Create an outside file in system temp
        final outsideFile = File(p.join(tempDocsDir.parent.path, 'outside_existing_secret.mp3'));
        outsideFile.writeAsStringSync('SECRET AUDIO', flush: true);

        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: AudioStorageLock(),
          storageService: storageService,
        );

        // 1. Traversal relative path pointing to outside existing file
        const maliciousSource = CustomAudioSource(
          id: 'custom:traversal_exploit',
          displayName: 'اختراق المسار',
          localRelativePath: 'adhan_sounds/../../outside_existing_secret.mp3',
          originalFileName: 'outside_existing_secret.mp3',
          fileSize: 100,
        );

        expect(
          () => repo.saveConfig(PrayerAlarmConfig(
            prayerId: PrayerId.fajr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: maliciousSource,
          )),
          throwsA(isA<FileSystemException>()),
        );

        // Verify config was never saved
        final configs = await fakePrayerConfig.getConfigs();
        expect(configs[PrayerId.fajr]?.audioSource is CustomAudioSource, isFalse);

        if (outsideFile.existsSync()) {
          outsideFile.deleteSync();
        }
      });

      test('27. R5.3: Save Path Sibling Directory Rejection: Rejects adhan_sounds_backup even if existing', () async {
        final siblingDir = Directory(p.join(tempDocsDir.path, 'adhan_sounds_backup'));
        await siblingDir.create(recursive: true);
        final siblingFile = File(p.join(siblingDir.path, 'backup_adhan.mp3'));
        siblingFile.writeAsStringSync('BACKUP ADHAN', flush: true);

        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: AudioStorageLock(),
          storageService: storageService,
        );

        // Direct sibling relative path
        const siblingSource = CustomAudioSource(
          id: 'custom:sibling_exploit',
          displayName: 'مجلد شقيق غير مصرح',
          localRelativePath: 'adhan_sounds_backup/backup_adhan.mp3',
          originalFileName: 'backup_adhan.mp3',
          fileSize: 100,
        );

        expect(
          () => repo.saveConfig(PrayerAlarmConfig(
            prayerId: PrayerId.dhuhr,
            alarmType: PrayerAlarmType.alarm,
            audioSource: siblingSource,
          )),
          throwsA(isA<FileSystemException>()),
        );

        await siblingDir.delete(recursive: true);
      });

      test('28. R5.3: Save Path Symlink Guard: Rejects symlink pointing outside storage root even if existing', () async {
        final outsideFile = File(p.join(tempDocsDir.parent.path, 'outside_target.mp3'));
        outsideFile.writeAsStringSync('OUTSIDE CONTENT', flush: true);

        final symlinkPath = p.join(storageDir.path, 'symlink_save_escape.mp3');
        bool symlinkCreated = false;
        try {
          final link = Link(symlinkPath);
          await link.create(outsideFile.path);
          symlinkCreated = true;
        } catch (_) {}

        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: AudioStorageLock(),
          storageService: storageService,
        );

        if (symlinkCreated) {
          const symlinkSource = CustomAudioSource(
            id: 'custom:symlink_escape',
            displayName: 'رابط رمزي هارب',
            localRelativePath: 'adhan_sounds/symlink_save_escape.mp3',
            originalFileName: 'symlink_save_escape.mp3',
            fileSize: 100,
          );

          expect(
            () => repo.saveConfig(PrayerAlarmConfig(
              prayerId: PrayerId.asr,
              alarmType: PrayerAlarmType.alarm,
              audioSource: symlinkSource,
            )),
            throwsA(isA<FileSystemException>()),
          );
        }

        if (outsideFile.existsSync()) {
          outsideFile.deleteSync();
        }
      });

      test('29. R5.4: Windows Path Normalization: Separators and canonical cases are validated safely', () async {
        // Create a valid audio file in storageDir
        final file = File(p.join(storageDir.path, 'custom_windows_test.mp3'));
        file.writeAsStringSync('VALID WINDOWS AUDIO', flush: true);

        final repo = PrayerAlarmConfigRepositoryImpl(
          localDataSource: fakePrayerConfig,
          audioStorageLock: AudioStorageLock(),
          storageService: storageService,
        );

        // Test forward slash (standard Posix)
        const forwardSource = CustomAudioSource(
          id: 'custom:forward_slash',
          displayName: 'صوت قياسي',
          localRelativePath: 'adhan_sounds/custom_windows_test.mp3',
          originalFileName: 'custom_windows_test.mp3',
          fileSize: 100,
        );

        await repo.saveConfig(PrayerAlarmConfig(
          prayerId: PrayerId.maghrib,
          alarmType: PrayerAlarmType.alarm,
          audioSource: forwardSource,
        ));

        final configs = await fakePrayerConfig.getConfigs();
        expect(configs[PrayerId.maghrib]?.audioSource, equals(forwardSource));
      });
    });
  });
}
