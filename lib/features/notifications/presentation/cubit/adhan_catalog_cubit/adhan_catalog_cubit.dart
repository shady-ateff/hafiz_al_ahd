import 'dart:async';
import 'dart:developer';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/adhan_storage_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_state.dart';

class AdhanCatalogCubit extends Cubit<AdhanCatalogState> {
  final BaseAdhanCatalogRepository catalogRepository;
  final BaseAudioDownloadService downloadService;
  final BasePlayableAudioResolver playableAudioResolver;
  final BaseAdhanStorageManagerService? _storageManagerService;
  final AudioPlayer _audioPlayer;

  final Map<String, StreamSubscription<AudioDownloadTask>> _taskSubscriptions = {};
  StreamSubscription<void>? _playerCompleteSub;

  AdhanCatalogCubit({
    required this.catalogRepository,
    required this.downloadService,
    required this.playableAudioResolver,
    BaseAdhanStorageManagerService? storageManagerService,
    AudioPlayer? audioPlayer,
  })  : _storageManagerService = storageManagerService,
        _audioPlayer = audioPlayer ?? AudioPlayer(),
        super(const AdhanCatalogState()) {
    _initPlayerListeners();
  }

  int _storageRefreshSequence = 0;

  void _initPlayerListeners() {
    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      emit(state.copyWith(clearPlaying: true, isPreviewPlaying: false));
    });
  }

  /// Loads catalog from repository. Supports offline cache fallback.
  /// Storage inspection runs independently so storage failures never block catalog display.
  Future<void> loadCatalog({bool forceRefresh = false}) async {
    emit(state.copyWith(status: CatalogStatus.loading, clearNotice: true));

    // Independent background storage inspection
    unawaited(refreshStorageInventory());

    final result = await catalogRepository.getCatalog(forceRefresh: forceRefresh);

    await result.fold(
      (failure) async {
        emit(state.copyWith(
          status: CatalogStatus.error,
          errorMessage: failure.message,
          isOffline: true,
        ));
      },
      (catalog) async {
        final isOffline = !CatalogConfig.isConfigured;

        final newPlayable = Map<String, AudioPlayableStatus>.from(state.playableStatuses);
        final newLocalSources = Map<String, CustomAudioSource>.from(state.localSources);
        final newTasks = Map<String, AudioDownloadTask>.from(state.downloadTasks);

        for (final entry in catalog.entries) {
          final resolution = await playableAudioResolver.resolveCatalogEntry(entry);
          newPlayable[entry.id] = resolution.status;
          if (resolution.isReady && resolution.localSource != null) {
            newLocalSources[entry.id] = resolution.localSource!;
          }

          final activeTask = downloadService.getTask(entry.id);
          if (activeTask != null) {
            newTasks[entry.id] = activeTask;
            _subscribeToTask(entry.id);
          }
        }

        emit(state.copyWith(
          status: CatalogStatus.loaded,
          catalog: catalog,
          playableStatuses: newPlayable,
          localSources: newLocalSources,
          downloadTasks: newTasks,
          isOffline: isOffline,
        ));
      },
    );
  }

  void _subscribeToTask(String entryId) {
    if (_taskSubscriptions.containsKey(entryId)) return;

    final sub = downloadService.watchTask(entryId).listen((task) {
      final updatedTasks = Map<String, AudioDownloadTask>.from(state.downloadTasks);
      updatedTasks[entryId] = task;

      emit(state.copyWith(downloadTasks: updatedTasks));

      if (task.status.isTerminal) {
        _taskSubscriptions[entryId]?.cancel();
        _taskSubscriptions.remove(entryId);
        // Refresh storage inventory upon task termination to clear reservations or reflect new files
        refreshStorageInventory();
      }
    });

    _taskSubscriptions[entryId] = sub;
  }

  /// Initiates byte-streamed download and atomic promotion of a remote entry.
  /// Enforces atomic quota admission guard prior to download dispatch.
  Future<void> startDownload(AdhanCatalogEntry entry) async {
    // 1. Quota Admission Guard (Hard Limit)
    if (_storageManagerService != null) {
      final quotaCheck = await _storageManagerService.checkQuota(requiredBytes: entry.fileSizeBytes);
      if (!quotaCheck.isAllowed) {
        emit(state.copyWith(
          userNotice:
              'لا يمكن بدء التنزيل: حجم الملف (${(entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت) يتجاوز كوتة كاش الأصوات المتبقية (${(quotaCheck.availableQuotaBytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت).',
        ));
        return;
      }
    }

    _subscribeToTask(entry.id);

    try {
      final result = await downloadService.downloadAudio(entry);

      await result.fold(
        (failure) async {
          emit(state.copyWith(
            userNotice: failure.message,
          ));
        },
        (customSource) async {
          final resolution = await playableAudioResolver.resolveCatalogEntry(entry);
          final newPlayable = Map<String, AudioPlayableStatus>.from(state.playableStatuses);
          final newLocalSources = Map<String, CustomAudioSource>.from(state.localSources);

          newPlayable[entry.id] = resolution.status;
          newLocalSources[entry.id] = customSource;

          emit(state.copyWith(
            playableStatuses: newPlayable,
            localSources: newLocalSources,
          ));
        },
      );
    } finally {
      // Always refresh storage inventory in finally block
      await refreshStorageInventory();
    }
  }

  /// Deletes a downloaded remote audio entry from private storage with JIT alarm safety revalidation.
  Future<bool> deleteDownloadedEntry(AdhanCatalogEntry entry) async {
    if (_storageManagerService == null) return false;

    // Stop preview if currently playing this audio
    if (state.isPreviewPlaying && state.playingAudioId == entry.id) {
      await stopPreview();
    }

    final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(entry);
    final relativePath = 'adhan_sounds/$targetFileName';

    try {
      final deleteResult = await _storageManagerService.deleteAudioFile(relativePath);

      if (entry.iqama != null) {
        final iqamaFileName = AudioDownloadServiceImpl.buildIqamaTargetFileName(entry);
        await _storageManagerService.deleteAudioFile('adhan_sounds/$iqamaFileName');
      }

      return deleteResult.fold(
        (failure) {
          emit(state.copyWith(userNotice: failure.message));
          return false;
        },
        (_) async {
          final newPlayable = Map<String, AudioPlayableStatus>.from(state.playableStatuses);
          final newLocalSources = Map<String, CustomAudioSource>.from(state.localSources);

          newPlayable[entry.id] = AudioPlayableStatus.requiresDownload;
          newLocalSources.remove(entry.id);

          emit(state.copyWith(
            playableStatuses: newPlayable,
            localSources: newLocalSources,
            userNotice: 'تم حذف الصوت بنجاح من الهاتف',
          ));
          return true;
        },
      );
    } finally {
      await refreshStorageInventory();
    }
  }

  /// Deletes an arbitrary audio file from local storage by relative path (e.g. from Storage Modal).
  Future<bool> deleteStorageFile(String relativePath) async {
    if (_storageManagerService == null) return false;

    try {
      final deleteResult = await _storageManagerService.deleteAudioFile(relativePath);
      return deleteResult.fold(
        (failure) {
          emit(state.copyWith(userNotice: failure.message));
          return false;
        },
        (_) async {
          // If a catalog entry matches this path, update playable status and local sources
          final newPlayable = Map<String, AudioPlayableStatus>.from(state.playableStatuses);
          final newLocalSources = Map<String, CustomAudioSource>.from(state.localSources);

          if (state.catalog != null) {
            for (final entry in state.catalog!.entries) {
              final targetName = AudioDownloadServiceImpl.buildTargetFileName(entry);
              if ('adhan_sounds/$targetName' == relativePath) {
                newPlayable[entry.id] = AudioPlayableStatus.requiresDownload;
                newLocalSources.remove(entry.id);
                if (state.isPreviewPlaying && state.playingAudioId == entry.id) {
                  await stopPreview();
                }
                break;
              }
            }
          }

          emit(state.copyWith(
            playableStatuses: newPlayable,
            localSources: newLocalSources,
            userNotice: 'تم حذف الملف بنجاح من الهاتف',
          ));
          return true;
        },
      );
    } finally {
      await refreshStorageInventory();
    }
  }

  /// Previews abandoned temporary files in `adhan_sounds/.tmp/` without deleting them (Phase 5.2 Dry-Run).
  Future<void> previewAbandonedTmpCleanup() async {
    if (_storageManagerService == null) return;

    final updatedInventory = await _storageManagerService.inspectStorage();
    final count = updatedInventory.abandonedTmpFiles.length;
    final freedKb = (updatedInventory.abandonedTmpBytes / 1024).toStringAsFixed(1);
    final message = count > 0
        ? 'معاينة: توجد $count ملفات مؤقتة مهجورة ($freedKb كيلوبايت) مرشحة للتنظيف التلقائي'
        : 'لا توجد ملفات مؤقتة مهجورة';

    emit(state.copyWith(
      storageInventory: updatedInventory,
      userNotice: message,
    ));
  }

  /// Manually refreshes the storage inventory snapshot with sequence monotonic race guard (Latest-Request-Wins).
  Future<void> refreshStorageInventory() async {
    if (_storageManagerService == null) return;
    final requestId = ++_storageRefreshSequence;
    emit(state.copyWith(storageStatus: StorageStatus.loading));

    try {
      final updatedInventory = await _storageManagerService.inspectStorage();
      if (requestId != _storageRefreshSequence) return;
      emit(state.copyWith(
        storageStatus: StorageStatus.loaded,
        storageInventory: updatedInventory,
        clearStorageError: true,
      ));
    } catch (e) {
      if (requestId != _storageRefreshSequence) return;
      emit(state.copyWith(
        storageStatus: StorageStatus.error,
        storageErrorMessage: 'تعذر فحص الذاكرة: $e',
      ));
    }
  }

  /// Cancels an active download.
  Future<void> cancelDownload(String entryId) async {
    await downloadService.cancelDownload(entryId);
    await refreshStorageInventory();
  }

  /// Plays preview for a built-in sound asset.
  Future<void> playBuiltInPreview(BuiltInAudioSource source, {bool isFajr = false}) async {
    try {
      if (state.isPreviewPlaying && state.playingAudioId == source.id) {
        await stopPreview();
        return;
      }

      await _audioPlayer.stop();

      final resolved = await playableAudioResolver.resolveAudio(source, isFajr: isFajr);
      final cleanPath = resolved.path.startsWith('assets/')
          ? resolved.path.substring(7)
          : resolved.path;

      emit(state.copyWith(
        playingAudioId: source.id,
        isPreviewPlaying: true,
      ));

      await _audioPlayer.play(AssetSource(cleanPath));
    } catch (e) {
      log("⚠️ [AdhanCatalogCubit] Built-in preview failed: $e");
      emit(state.copyWith(clearPlaying: true, isPreviewPlaying: false));
    }
  }

  /// Plays preview for a remote catalog entry ONLY from locally verified physical file.
  /// Strictly rejects remote URL streaming.
  Future<void> playRemoteEntryPreview(AdhanCatalogEntry entry) async {
    try {
      if (state.isPreviewPlaying && state.playingAudioId == entry.id) {
        await stopPreview();
        return;
      }

      // 1. Verify local presence and physical path
      final resolution = await playableAudioResolver.resolveCatalogEntry(entry);
      if (!resolution.isReady || resolution.physicalPath == null) {
        // STRICT SAFETY: Do NOT stream from remote URL!
        emit(state.copyWith(
          userNotice: 'يجب تنزيل الأذان أولاً للاستماع إليه',
        ));
        return;
      }

      await _audioPlayer.stop();

      emit(state.copyWith(
        playingAudioId: entry.id,
        isPreviewPlaying: true,
      ));

      // 2. Play strictly from device file
      await _audioPlayer.play(DeviceFileSource(resolution.physicalPath!));
    } catch (e) {
      log("⚠️ [AdhanCatalogCubit] Remote entry preview failed: $e");
      emit(state.copyWith(clearPlaying: true, isPreviewPlaying: false));
    }
  }

  /// Stops actively running audio preview.
  Future<void> stopPreview() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    emit(state.copyWith(clearPlaying: true, isPreviewPlaying: false));
  }

  /// Clears user notice string.
  void clearNotice() {
    emit(state.copyWith(clearNotice: true));
  }

  @override
  Future<void> close() async {
    for (final sub in _taskSubscriptions.values) {
      await sub.cancel();
    }
    _taskSubscriptions.clear();
    await _playerCompleteSub?.cancel();
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    return super.close();
  }
}

