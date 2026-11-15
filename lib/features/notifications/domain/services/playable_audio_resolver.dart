import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';

/// Represents a verified, playable audio path ready for consumption by
/// [TransitionCoordinator], [NativeAlarmService], or audio preview engines.
class ResolvedPlayableAudio extends Equatable {
  /// Local device file path or bundled Flutter asset path.
  final String path;

  /// True if [path] refers to an in-app bundled asset (`assets/...`).
  final bool isAsset;

  /// True if the requested source was unavailable and a safe fallback was returned.
  final bool isFallback;

  /// Human-readable explanation if fallback was triggered.
  final String? fallbackReason;

  const ResolvedPlayableAudio({
    required this.path,
    required this.isAsset,
    this.isFallback = false,
    this.fallbackReason,
  });

  @override
  List<Object?> get props => [path, isAsset, isFallback, fallbackReason];

  @override
  String toString() =>
      'ResolvedPlayableAudio(path: $path, isAsset: $isAsset, isFallback: $isFallback)';
}

/// Status of an audio source in terms of local availability.
enum AudioPlayableStatus {
  /// Audio file exists locally (or is a valid bundled asset) and is ready for playback.
  ready,

  /// Audio is a valid remote catalog entry that has not been downloaded yet.
  requiresDownload,

  /// Audio file is missing on disk or metadata is invalid.
  missingOrInvalid,
}

/// Resolution result for a remote catalog entry.
class CatalogEntryResolution extends Equatable {
  final AudioPlayableStatus status;
  final CustomAudioSource? localSource;
  final String? physicalPath;

  const CatalogEntryResolution({
    required this.status,
    this.localSource,
    this.physicalPath,
  });

  bool get isReady => status == AudioPlayableStatus.ready;
  bool get requiresDownload => status == AudioPlayableStatus.requiresDownload;
  bool get isMissingOrInvalid => status == AudioPlayableStatus.missingOrInvalid;

  @override
  List<Object?> get props => [status, localSource, physicalPath];
}

/// Architectural contract ensuring all audio sources are physically verified
/// before delivery to the alarm engine.
///
/// ## Missing Audio Fallback Safety Rule
/// If a user-selected [CustomAudioSource] has been deleted from disk or corrupted:
/// - The resolver cleanly returns the default built-in sound (`BuiltInAudioSource.defaultMishary`).
/// - It logs an explicit warning.
/// - It NEVER mutates or erases user preferences silently.
/// - It NEVER initiates network downloads during alarm resolution.
abstract class BasePlayableAudioResolver {
  /// Resolves [source] to a verified playable audio target.
  Future<ResolvedPlayableAudio> resolveAudio(
    AudioSourceConfig source, {
    required bool isFajr,
  });

  /// Resolves the verified playable audio target for Iqama.
  ///
  /// If [source] is a [CustomAudioSource] with a valid [iqamaLocalRelativePath]
  /// on disk, it is returned. Otherwise, returns a safe fallback to built-in
  /// iqama sound (`assets/sounds/iqama_sound.mp3`).
  Future<ResolvedPlayableAudio> resolveIqamaAudio(
    AudioSourceConfig source,
  );

  /// Resolves the playable availability of a remote catalog entry.
  Future<CatalogEntryResolution> resolveCatalogEntry(
    AdhanCatalogEntry entry,
  );

  /// Resolves a remote catalog entry into a registered [CustomAudioSource] if
  /// already downloaded and existing locally. Returns null if not downloaded.
  Future<CustomAudioSource?> resolveLocalCustomSource(
    AdhanCatalogEntry entry,
  );

  /// Quickly checks whether an [AudioSourceConfig] can be played locally immediately.
  Future<bool> isAudioPlayableLocally(
    AudioSourceConfig source,
  );
}

