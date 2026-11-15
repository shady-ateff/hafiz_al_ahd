import 'dart:convert';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/storage_management_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';

/// Concrete implementation of [BaseAdhanStorageManagerService].
///
/// Responsible for byte-accurate filesystem inspection of the `adhan_sounds` directory,
/// ownership classification, active alarm reference protection, in-flight reservation accounting,
/// and safe eviction candidate ranking.
class AdhanStorageManagerServiceImpl implements BaseAdhanStorageManagerService {
  final CustomAudioStorageService storageService;
  final BasePrayerAlarmConfigLocalDataSource prayerConfigDataSource;
  final BaseAudioDownloadService downloadService;
  final BaseAudioStorageLock audioStorageLock;
  final SharedPreferences prefs;
  final int quotaLimitBytes;
  final DateTime Function()? nowProvider;

  static final RegExp _userCustomRegex =
      RegExp(r'^custom_\d+\.(mp3|m4a|wav)$', caseSensitive: false);

  static final RegExp _remoteCacheRegex =
      RegExp(r'^remote_[a-zA-Z0-9_]+_[a-f0-9]{16,64}\.(mp3|m4a|wav)$',
          caseSensitive: false);

  static final RegExp _stagingTmpRegex =
      RegExp(r'^dl_\d+_\d+\.tmp$', caseSensitive: false);

  AdhanStorageManagerServiceImpl({
    required this.storageService,
    required this.prayerConfigDataSource,
    required this.downloadService,
    required this.audioStorageLock,
    required this.prefs,
    int? quotaLimitBytes,
    this.nowProvider,
  }) : quotaLimitBytes = quotaLimitBytes ?? kRemoteAudioCacheQuotaBytes;

  static String _toPosix(String path) =>
      p.normalize(path).replaceAll('\\', '/');

  DateTime get _now => nowProvider != null ? nowProvider!() : DateTime.now();

  @override
  Future<Set<String>> getActiveAlarmAudioPaths() async {
    final configs = await prayerConfigDataSource.getConfigs();
    final activePaths = <String>{};

    for (final entry in configs.entries) {
      final config = entry.value;
      if (config.audioSource is CustomAudioSource) {
        final custom = config.audioSource as CustomAudioSource;
        final normPath = _toPosix(custom.localRelativePath);
        if (normPath.isNotEmpty) {
          activePaths.add(normPath);
        }
      }
    }
    return activePaths;
  }

  @override
  Future<AdhanStorageInventory> inspectStorage({
    Duration ageThreshold = const Duration(minutes: 60),
  }) async {
    final storageDir = await storageService.getStorageDirectory();
    if (!await storageDir.exists()) {
      return AdhanStorageInventory.empty(
        remoteCacheQuotaBytes: quotaLimitBytes,
      );
    }

    final canonicalRoot = p.canonicalize(storageDir.path);
    final now = _now;

    // 1. Correlate Active Prayer Alarm Audio References
    final configs = await prayerConfigDataSource.getConfigs();
    final activeAlarmPaths = <String>{};
    final activePathsToPrayerNames = <String, List<String>>{};

    for (final entry in configs.entries) {
      final config = entry.value;
      if (config.audioSource is CustomAudioSource) {
        final custom = config.audioSource as CustomAudioSource;
        final normPath = _toPosix(custom.localRelativePath);
        if (normPath.isNotEmpty) {
          activeAlarmPaths.add(normPath);
          activePathsToPrayerNames
              .putIfAbsent(normPath, () => [])
              .add(entry.key.arabicName);
        }
      }
    }

    // 2. Account for In-Flight Download Reservations
    final activeTasks = downloadService.getActiveTasks();
    int reservedInFlightBytes = 0;
    final activeTempPrefixes = downloadService.getActiveTempPrefixes();

    for (final task in activeTasks) {
      if (task.status.isActive) {
        final total = task.progress.totalBytes;
        if (total != null && total > 0) {
          reservedInFlightBytes += total;
        }
      }
    }

    // 3. Scan Filesystem with Strict Canonical Deduplication & Traversal Protection
    final scannedCanonicalPaths = <String>{};
    final allFiles = <StorageAudioFile>[];
    final abandonedTmp = <StorageAudioFile>[];
    final evictionCandidates = <StorageAudioFile>[];

    int totalDirectoryBytes = 0;
    int remoteCacheBytes = 0;
    int userCustomBytes = 0;
    int stagingTmpBytes = 0;
    int unmanagedBytes = 0;

    List<FileSystemEntity> entities = const [];
    try {
      entities = storageDir.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      // Permission denied or missing directory -> return empty inventory
      return AdhanStorageInventory.empty(
        remoteCacheQuotaBytes: quotaLimitBytes,
      );
    }

    for (final entity in entities) {
      if (entity is! File) continue;

      final canonicalPath = p.canonicalize(entity.path);

      // Traversal guard: Strictly ignore files outside storage root (e.g. symlinks pointing out)
      if (!p.isWithin(canonicalRoot, canonicalPath)) {
        continue;
      }

      // Canonical deduplication: ensure no duplicate byte counting
      if (!scannedCanonicalPaths.add(canonicalPath)) {
        continue;
      }

      int fileLength = 0;
      DateTime lastModified = now;

      try {
        final stat = entity.statSync();
        fileLength = stat.size;
        lastModified = stat.modified;
      } on FileSystemException {
        // File was deleted or locked during scan -> safely skip
        continue;
      } catch (_) {
        continue;
      }

      final fileName = p.basename(entity.path);
      final relPath =
          _toPosix(p.relative(entity.path, from: storageDir.parent.path));
      final ext = p.extension(fileName).toLowerCase();

      // Determine directory context
      final parentCanonical = p.canonicalize(p.dirname(entity.path));
      final tmpDirCanonical = p.canonicalize(p.join(canonicalRoot, '.tmp'));
      final isInsideTmp = parentCanonical == tmpDirCanonical;
      final isInsideRoot = parentCanonical == canonicalRoot;

      StorageFileClassification classification;
      bool isProtected = false;
      String? protectedReason;

      if (isInsideTmp) {
        final isStagingFormat = _stagingTmpRegex.hasMatch(fileName);
        if (isStagingFormat) {
          classification = StorageFileClassification.stagingTmp;
          stagingTmpBytes += fileLength;

          final isActiveDownload =
              activeTempPrefixes.any((prefix) => fileName.startsWith(prefix));
          final fileAge = now.difference(lastModified);
          final isAbandoned = !isActiveDownload && fileAge > ageThreshold;

          if (isAbandoned) {
            isProtected = false;
            protectedReason = null;
          } else {
            isProtected = true;
            protectedReason = isActiveDownload
                ? 'تنزيل نشط قيد التنفيذ'
                : 'ملف مؤقت حديث قيد الاستخدام';
          }
        } else {
          // Unknown file in .tmp
          classification = StorageFileClassification.unmanaged;
          unmanagedBytes += fileLength;
          isProtected = true;
          protectedReason = 'ملف غير معروف في المجلد المؤقت';
        }
      } else if (isInsideRoot) {
        final isAllowedExt =
            CustomAudioStorageService.allowedExtensions.contains(ext);

        if (!isAllowedExt || fileLength <= 0) {
          // Unsupported extension or 0-byte corrupt file
          classification = StorageFileClassification.unmanaged;
          unmanagedBytes += fileLength;
          isProtected = true;
          protectedReason = fileLength <= 0
              ? 'ملف فارغ أو تالف (0 بايت)'
              : 'امتداد صوتي غير معتمد ($ext)';
        } else if (_userCustomRegex.hasMatch(fileName)) {
          classification = StorageFileClassification.userCustom;
          userCustomBytes += fileLength;
          isProtected = true;
          protectedReason = 'ملف صوتي مستورد من المستخدم';
        } else if (_remoteCacheRegex.hasMatch(fileName)) {
          classification = StorageFileClassification.remoteCache;
          remoteCacheBytes += fileLength;

          final isUsedInAlarm = activeAlarmPaths.contains(relPath);
          if (isUsedInAlarm) {
            isProtected = true;
            final prayers =
                activePathsToPrayerNames[relPath]?.join('، ') ?? 'منبه الصلاة';
            protectedReason = 'مستخدم في صلاة: $prayers';
          } else {
            isProtected = false;
            protectedReason = null;
          }
        } else {
          // Unrecognized filename in root
          classification = StorageFileClassification.unmanaged;
          unmanagedBytes += fileLength;
          isProtected = true;
          protectedReason = 'ملف غير معروف في مجلد الأصوات';
        }
      } else {
        // Unexpected subfolder within storageDir
        classification = StorageFileClassification.unmanaged;
        unmanagedBytes += fileLength;
        isProtected = true;
        protectedReason = 'ملف داخل مجلد فرعي غير معروف';
      }

      totalDirectoryBytes += fileLength;

      final storageFile = StorageAudioFile(
        relativePath: relPath,
        absolutePath: entity.path,
        fileName: fileName,
        byteLength: fileLength,
        lastModified: lastModified,
        classification: classification,
        isProtected: isProtected,
        protectedReason: protectedReason,
      );

      allFiles.add(storageFile);

      if (classification == StorageFileClassification.stagingTmp &&
          !isProtected) {
        abandonedTmp.add(storageFile);
      } else if (storageFile.isSafeToEvict) {
        evictionCandidates.add(storageFile);
      }
    }

    // 4. Sort Safe Eviction Candidates (Oldest modified first, then largest byte length)
    evictionCandidates.sort((a, b) {
      final cmp = a.lastModified.compareTo(b.lastModified);
      if (cmp != 0) return cmp;
      return b.byteLength.compareTo(a.byteLength);
    });

    return AdhanStorageInventory(
      totalDirectoryBytes: totalDirectoryBytes,
      remoteCacheBytes: remoteCacheBytes,
      userCustomBytes: userCustomBytes,
      stagingTmpBytes: stagingTmpBytes,
      unmanagedBytes: unmanagedBytes,
      reservedInFlightBytes: reservedInFlightBytes,
      remoteCacheQuotaBytes: quotaLimitBytes,
      files: allFiles,
      activeAlarmPaths: activeAlarmPaths,
      abandonedTmpFiles: abandonedTmp,
      evictionCandidates: evictionCandidates,
    );
  }

  @override
  Future<QuotaCheckResult> checkQuota({required int requiredBytes}) async {
    final inventory = await inspectStorage();
    final currentUsage = inventory.effectiveRemoteUsageBytes;
    final projectedUsage = currentUsage + requiredBytes;
    final isAllowed = projectedUsage <= inventory.remoteCacheQuotaBytes;
    final availableQuota = inventory.availableRemoteQuotaBytes;
    final deficit =
        isAllowed ? 0 : (projectedUsage - inventory.remoteCacheQuotaBytes);

    final suggestedCandidates = <StorageAudioFile>[];
    if (deficit > 0) {
      int accumulatedFreed = 0;
      for (final candidate in inventory.evictionCandidates) {
        suggestedCandidates.add(candidate);
        accumulatedFreed += candidate.byteLength;
        if (accumulatedFreed >= deficit) {
          break;
        }
      }
    }

    return QuotaCheckResult(
      isAllowed: isAllowed,
      requiredBytes: requiredBytes,
      availableQuotaBytes: availableQuota,
      currentUsageBytes: currentUsage,
      quotaLimitBytes: inventory.remoteCacheQuotaBytes,
      deficitBytes: deficit,
      suggestedEvictionCandidates: suggestedCandidates,
    );
  }

  @override
  Future<List<StorageAudioFile>> getAbandonedTmpFiles({
    Duration ageThreshold = const Duration(minutes: 60),
  }) async {
    final inventory = await inspectStorage(ageThreshold: ageThreshold);
    return inventory.abandonedTmpFiles;
  }

  @override
  Future<List<StorageAudioFile>> getSafeEvictionCandidates() async {
    final inventory = await inspectStorage();
    return inventory.evictionCandidates;
  }

  @override
  Future<Either<StorageDeletionFailure, void>> deleteAudioFile(
    String relativePath, {
    bool isUserExplicit = false,
  }) async {
    return await audioStorageLock.synchronized(() async {
      // 1. Path safety and traversal guard
      if (relativePath.contains('..') ||
          relativePath.startsWith('/') ||
          relativePath.startsWith('\\')) {
        return const Left(StorageDeletionSecurityFailure());
      }

      final normRel = _toPosix(relativePath);
      if (!normRel.startsWith('adhan_sounds/')) {
        return const Left(StorageDeletionSecurityFailure());
      }

      final storageDir = await storageService.getStorageDirectory();
      final canonicalRoot = p.canonicalize(storageDir.path);

      // Resolve physical path relative to storageDir parent
      final physicalPath = p.normalize(p.join(storageDir.parent.path, normRel));
      final canonicalTarget = p.canonicalize(physicalPath);

      if (!p.isWithin(canonicalRoot, canonicalTarget)) {
        return const Left(StorageDeletionSecurityFailure());
      }

      final file = File(canonicalTarget);
      if (!await file.exists()) {
        return const Left(StorageDeletionNotFoundFailure());
      }

      // Symlink Security Guard: Resolve real symbolic target and enforce canonical boundary
      try {
        final resolvedRoot = p.canonicalize(await storageDir.resolveSymbolicLinks());
        final realTarget = p.canonicalize(await file.resolveSymbolicLinks());
        if (!p.isWithin(resolvedRoot, realTarget)) {
          return const Left(StorageDeletionSecurityFailure('الرابط الرمزي يشير إلى مسار خارج مجلد الأصوات'));
        }
      } catch (_) {
        return const Left(StorageDeletionSecurityFailure('تعذر التحقق من أمان الرابط الرمزي'));
      }

      final fileName = p.basename(canonicalTarget);
      final ext = p.extension(fileName).toLowerCase();
      final parentCanonical = p.canonicalize(p.dirname(canonicalTarget));
      final tmpDirCanonical = p.canonicalize(p.join(canonicalRoot, '.tmp'));
      final isInsideTmp = parentCanonical == tmpDirCanonical;
      final isInsideRoot = parentCanonical == canonicalRoot;

      // 2. Atomic Just-In-Time Revalidation under lock: Query live active alarm configurations
      final configs = await prayerConfigDataSource.getConfigs();
      final assignedPrayers = <String>[];
      for (final entry in configs.entries) {
        final config = entry.value;
        if (config.audioSource is CustomAudioSource) {
          final custom = config.audioSource as CustomAudioSource;
          if (_toPosix(custom.localRelativePath) == normRel) {
            assignedPrayers.add(entry.key.arabicName);
          }
        }
      }

      // Also check global adhan audio source in SharedPreferences
      final globalSourceStr = prefs.getString('global_adhan_audio_source');
      if (globalSourceStr != null) {
        try {
          final decoded = jsonDecode(globalSourceStr) as Map<String, dynamic>;
          if (decoded['type'] == 'custom' && decoded['localRelativePath'] != null) {
            if (_toPosix(decoded['localRelativePath'] as String) == normRel) {
              assignedPrayers.add('الافتراضي العام للصلوات');
            }
          }
        } catch (_) {}
      }

      if (assignedPrayers.isNotEmpty) {
        return Left(StorageDeletionActiveAlarmFailure(assignedPrayers));
      }

      // 3. Revalidate In-Flight Download Tasks
      final activeTempPrefixes = downloadService.getActiveTempPrefixes();
      if (activeTempPrefixes.any((prefix) => fileName.startsWith(prefix))) {
        return const Left(StorageDeletionProtectedFailure('تنزيل نشط قيد التنفيذ'));
      }

      // 4. Revalidate Ownership Classification
      if (isInsideTmp) {
        // Direct manual deletion of temporary files is protected.
        // Temporary files are managed strictly through scheduled GC preview (deferred).
        return const Left(StorageDeletionProtectedFailure('الملفات المؤقتة مدارة آلياً ومحمية من الحذف اليدوي'));
      } else if (isInsideRoot) {
        final isAllowedExt =
            CustomAudioStorageService.allowedExtensions.contains(ext);
        if (!isAllowedExt) {
          return const Left(StorageDeletionProtectedFailure('ملف بامتداد غير معتمد أو غير مدار'));
        }

        if (_userCustomRegex.hasMatch(fileName)) {
          if (!isUserExplicit) {
            return const Left(StorageDeletionProtectedFailure(
                'لا يمكن حذف الملفات الخاصة بالمستخدم إلا بتأكيد صريح من المستخدم'));
          }
        } else if (_remoteCacheRegex.hasMatch(fileName)) {
          // Unreferenced remote cache file allowed for deletion
        } else {
          return const Left(StorageDeletionProtectedFailure('ملف غير مصنف في الكاش السحابي'));
        }
      } else {
        return const Left(StorageDeletionSecurityFailure('ملف داخل مجلد فرعي غير مصرح به'));
      }

      // 5. Physical Deletion Execution
      try {
        await file.delete();
        return const Right(null);
      } on FileSystemException catch (e) {
        return Left(StorageDeletionIoFailure(e.message));
      } catch (e) {
        return Left(StorageDeletionIoFailure(e.toString()));
      }
    });
  }

  @override
  Future<StorageCleanupSummary> cleanupAbandonedTmpFiles({
    Duration ageThreshold = const Duration(minutes: 60),
  }) async {
    // NOTE (Phase 5.2): Physical GC execution is deferred pending Phase authorization.
    // In Phase 5.2, this method operates strictly as a dry-run / preview inspection.
    // Zero files are physically unlinked.
    await inspectStorage(ageThreshold: ageThreshold);

    return const StorageCleanupSummary(
      deletedCount: 0,
      freedBytes: 0,
      deletedFileNames: [],
    );
  }
}
