import 'dart:developer';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';

/// Concrete implementation of [BasePlayableAudioResolver].
///
/// ## Architectural Guarantees:
/// 1. **Pure Resolution**: Performs local filesystem checks only. Never initiates network downloads
///    during resolution or alarm scheduling.
/// 2. **Non-Destructive Fallback**: If a custom file is missing from disk, it falls back to
///    [BuiltInAudioSource.defaultMishary] for the current alarm without mutating or overwriting
///    the user's stored preferences.
/// 3. **Fast Local Verification**: Avoids re-computing expensive SHA-256 digests on every resolution
///    call once the file is registered/promoted locally.
class PlayableAudioResolverImpl implements BasePlayableAudioResolver {
  final CustomAudioStorageService storageService;

  const PlayableAudioResolverImpl({
    required this.storageService,
  });

  @override
  Future<ResolvedPlayableAudio> resolveAudio(
    AudioSourceConfig source, {
    required bool isFajr,
  }) async {
    // 1. Built-in Asset Source
    if (source is BuiltInAudioSource) {
      final assetPath = source.resolveAssetPath(isFajr: isFajr);
      if (assetPath.isNotEmpty) {
        return ResolvedPlayableAudio(
          path: assetPath,
          isAsset: true,
          isFallback: false,
        );
      }
      final fallback = AudioSourceConfig.defaultBuiltInFallback(isFajr: isFajr)
          .resolveAssetPath(isFajr: isFajr);
      return ResolvedPlayableAudio(
        path: fallback,
        isAsset: true,
        isFallback: true,
        fallbackReason: 'مسار ملف الصوت المدمج غير محدد',
      );
    }

    // 2. Custom Audio Source (Local File)
    if (source is CustomAudioSource) {
      // Path traversal security check
      if (source.localRelativePath.contains('..') ||
          source.localRelativePath.startsWith('/') ||
          source.localRelativePath.startsWith('\\')) {
        log("⚠️ [PlayableAudioResolver] Traversal attempt in '${source.localRelativePath}'. Using built-in fallback.");
        final fallback = AudioSourceConfig.defaultBuiltInFallback(isFajr: isFajr)
            .resolveAssetPath(isFajr: isFajr);
        return ResolvedPlayableAudio(
          path: fallback,
          isAsset: true,
          isFallback: true,
          fallbackReason: 'المسار الصوتي غير آمن ويحتوي على تلاعب بالمسارات',
        );
      }

      final storageDir = await storageService.getStorageDirectory();
      final resolvedPath =
          p.normalize(p.join(storageDir.parent.path, source.localRelativePath));

      if (!resolvedPath.startsWith(storageDir.path)) {
        log("⚠️ [PlayableAudioResolver] Path outside storage in '$resolvedPath'. Using built-in fallback.");
        final fallback = AudioSourceConfig.defaultBuiltInFallback(isFajr: isFajr)
            .resolveAssetPath(isFajr: isFajr);
        return ResolvedPlayableAudio(
          path: fallback,
          isAsset: true,
          isFallback: true,
          fallbackReason: 'المسار الصوتي خارج مجلد التطبيق المخصص',
        );
      }

      final file = File(resolvedPath);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          return ResolvedPlayableAudio(
            path: resolvedPath,
            isAsset: false,
            isFallback: false,
          );
        }
      }

      // Non-destructive fallback for missing or 0-byte custom audio
      log("⚠️ [PlayableAudioResolver] Custom audio missing or empty at '$resolvedPath'. Non-destructive fallback to built-in default.");
      final fallback = AudioSourceConfig.defaultBuiltInFallback(isFajr: isFajr)
          .resolveAssetPath(isFajr: isFajr);
      return ResolvedPlayableAudio(
        path: fallback,
        isAsset: true,
        isFallback: true,
        fallbackReason: 'ملف الأذان المخصص غير موجود على الهاتف',
      );
    }

    // 3. Unknown Audio Source Type Fallback
    log("⚠️ [PlayableAudioResolver] Unknown audio source type '${source.runtimeType}'. Using built-in fallback.");
    final fallback = AudioSourceConfig.defaultBuiltInFallback(isFajr: isFajr)
        .resolveAssetPath(isFajr: isFajr);
    return ResolvedPlayableAudio(
      path: fallback,
      isAsset: true,
      isFallback: true,
      fallbackReason: 'نوع مصدر الصوت غير معروف',
    );
  }

  @override
  Future<CatalogEntryResolution> resolveCatalogEntry(
    AdhanCatalogEntry entry,
  ) async {
    if (!entry.isValid) {
      return const CatalogEntryResolution(
        status: AudioPlayableStatus.missingOrInvalid,
      );
    }

    final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(entry);
    final storageDir = await storageService.getStorageDirectory();
    final targetFile = File(p.join(storageDir.path, targetFileName));

    if (await targetFile.exists()) {
      final length = await targetFile.length();
      if (length > 0) {
        final localSource = CustomAudioSource(
          id: 'custom:${entry.id}',
          displayName: entry.displayName,
          localRelativePath: p.join('adhan_sounds', targetFileName),
          originalFileName: p.basename(entry.objectKey),
          fileSize: length,
        );
        return CatalogEntryResolution(
          status: AudioPlayableStatus.ready,
          localSource: localSource,
          physicalPath: targetFile.path,
        );
      }
    }

    return const CatalogEntryResolution(
      status: AudioPlayableStatus.requiresDownload,
    );
  }

  @override
  Future<CustomAudioSource?> resolveLocalCustomSource(
    AdhanCatalogEntry entry,
  ) async {
    final resolution = await resolveCatalogEntry(entry);
    if (resolution.isReady) {
      return resolution.localSource;
    }
    return null;
  }

  @override
  Future<bool> isAudioPlayableLocally(AudioSourceConfig source) async {
    if (source is BuiltInAudioSource) {
      return true;
    }
    if (source is CustomAudioSource) {
      try {
        final storageDir = await storageService.getStorageDirectory();
        final resolvedPath = p.normalize(
            p.join(storageDir.parent.path, source.localRelativePath));
        if (!resolvedPath.startsWith(storageDir.path)) {
          return false;
        }
        final file = File(resolvedPath);
        return await file.exists() && (await file.length()) > 0;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}

