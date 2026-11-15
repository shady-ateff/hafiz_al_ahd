import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';

enum CatalogStatus { initial, loading, loaded, error }
enum StorageStatus { initial, loading, loaded, error }

class AdhanCatalogState extends Equatable {
  final CatalogStatus status;
  final StorageStatus storageStatus;
  final AdhanCatalog? catalog;
  final bool isOffline;
  final String? errorMessage;
  final String? storageErrorMessage;
  final Map<String, AudioDownloadTask> downloadTasks;
  final Map<String, AudioPlayableStatus> playableStatuses;
  final Map<String, CustomAudioSource> localSources;
  final String? playingAudioId;
  final bool isPreviewPlaying;
  final String? userNotice;
  final AdhanStorageInventory? storageInventory;

  const AdhanCatalogState({
    this.status = CatalogStatus.initial,
    this.storageStatus = StorageStatus.initial,
    this.catalog,
    this.isOffline = false,
    this.errorMessage,
    this.storageErrorMessage,
    this.downloadTasks = const {},
    this.playableStatuses = const {},
    this.localSources = const {},
    this.playingAudioId,
    this.isPreviewPlaying = false,
    this.userNotice,
    this.storageInventory,
  });

  bool get isStorageLoaded => storageStatus == StorageStatus.loaded && storageInventory != null;

  /// Effective ratio of remote cache consumption against the 150 MiB quota.
  double get quotaUsageRatio {
    if (storageInventory == null || storageInventory!.remoteCacheQuotaBytes <= 0) return 0.0;
    return (storageInventory!.effectiveRemoteUsageBytes / storageInventory!.remoteCacheQuotaBytes).clamp(0.0, 1.0);
  }

  /// Warning condition: Usage is at or above 85% or remaining is below 22.5 MiB, but below 100%.
  bool get isQuotaWarning {
    if (storageInventory == null) return false;
    final remaining = storageInventory!.availableRemoteQuotaBytes;
    final warningBytes = (storageInventory!.remoteCacheQuotaBytes * 0.15).toInt(); // 22.5 MiB
    return (quotaUsageRatio >= 0.85 || remaining < warningBytes) && !isQuotaExceeded;
  }

  /// Full / Exceeded condition: Effective usage equals or exceeds quota limit.
  bool get isQuotaExceeded {
    if (storageInventory == null) return false;
    return storageInventory!.effectiveRemoteUsageBytes >= storageInventory!.remoteCacheQuotaBytes;
  }

  AdhanCatalogState copyWith({
    CatalogStatus? status,
    StorageStatus? storageStatus,
    AdhanCatalog? catalog,
    bool? isOffline,
    String? errorMessage,
    String? storageErrorMessage,
    Map<String, AudioDownloadTask>? downloadTasks,
    Map<String, AudioPlayableStatus>? playableStatuses,
    Map<String, CustomAudioSource>? localSources,
    String? playingAudioId,
    bool? isPreviewPlaying,
    String? userNotice,
    AdhanStorageInventory? storageInventory,
    bool clearPlaying = false,
    bool clearNotice = false,
    bool clearStorageError = false,
  }) {
    return AdhanCatalogState(
      status: status ?? this.status,
      storageStatus: storageStatus ?? this.storageStatus,
      catalog: catalog ?? this.catalog,
      isOffline: isOffline ?? this.isOffline,
      errorMessage: errorMessage ?? this.errorMessage,
      storageErrorMessage: clearStorageError ? null : (storageErrorMessage ?? this.storageErrorMessage),
      downloadTasks: downloadTasks ?? this.downloadTasks,
      playableStatuses: playableStatuses ?? this.playableStatuses,
      localSources: localSources ?? this.localSources,
      playingAudioId: clearPlaying ? null : (playingAudioId ?? this.playingAudioId),
      isPreviewPlaying: isPreviewPlaying ?? this.isPreviewPlaying,
      userNotice: clearNotice ? null : (userNotice ?? this.userNotice),
      storageInventory: storageInventory ?? this.storageInventory,
    );
  }

  @override
  List<Object?> get props => [
        status,
        storageStatus,
        catalog,
        isOffline,
        errorMessage,
        storageErrorMessage,
        downloadTasks,
        playableStatuses,
        localSources,
        playingAudioId,
        isPreviewPlaying,
        userNotice,
        storageInventory,
      ];
}
