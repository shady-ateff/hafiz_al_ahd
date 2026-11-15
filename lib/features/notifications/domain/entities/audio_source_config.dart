import 'package:flutter/foundation.dart';

/// Sealed hierarchy defining audio sources for prayer alarms.
sealed class AudioSourceConfig {
  final String id;
  final String displayName;

  const AudioSourceConfig({
    required this.id,
    required this.displayName,
  });

  Map<String, dynamic> toJson();

  /// Deserializes an audio source from a JSON map with safe fallbacks.
  /// If the type is unknown or fields are malformed, returns the default built-in source without throwing.
  static AudioSourceConfig fromJson(Map<String, dynamic> json, {bool isFajr = false}) {
    try {
      final type = json['type'] as String?;
      switch (type) {
        case 'builtIn':
          return BuiltInAudioSource.fromJson(json);
        case 'custom':
          return CustomAudioSource.fromJson(json);
        default:
          return defaultBuiltInFallback(isFajr: isFajr);
      }
    } catch (_) {
      // Handles known discriminators with malformed fields without throwing
      return defaultBuiltInFallback(isFajr: isFajr);
    }
  }

  /// Default built-in audio source (Sheikh Mishary Rashid Al-Afasy).
  static const BuiltInAudioSource defaultMishary = BuiltInAudioSource(
    id: 'builtIn:mishary_alafasy',
    displayName: 'الشيخ مشاري راشد العفاسي',
    assetPath: 'assets/sounds/adhan.mp3',
    fajrAssetPath: 'assets/sounds/fajr_azan.mp3',
  );

  /// Default built-in audio source fallback.
  static BuiltInAudioSource defaultBuiltInFallback({bool isFajr = false}) => defaultMishary;
}

/// Built-in app asset audio source.
@immutable
class BuiltInAudioSource extends AudioSourceConfig {
  final String assetPath;
  final String? fajrAssetPath;

  const BuiltInAudioSource({
    required super.id,
    required super.displayName,
    required this.assetPath,
    this.fajrAssetPath,
  });

  /// Resolves the specific audio asset path for the given prayer context.
  /// If it is Fajr and a specific [fajrAssetPath] is present, returns [fajrAssetPath]; otherwise returns [assetPath].
  String resolveAssetPath({bool isFajr = false}) {
    if (isFajr && fajrAssetPath != null && fajrAssetPath!.isNotEmpty) {
      return fajrAssetPath!;
    }
    return assetPath;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'builtIn',
        'id': id,
        'displayName': displayName,
        'assetPath': assetPath,
        if (fajrAssetPath != null) 'fajrAssetPath': fajrAssetPath,
      };

  factory BuiltInAudioSource.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? 'builtIn:mishary_alafasy';

    // Normalize legacy v1 IDs to the unified Mishary Alafasy source
    if (id == 'builtIn:default_general' ||
        id == 'builtIn:default_fajr' ||
        id == 'builtIn:mishary_alafasy') {
      return AudioSourceConfig.defaultMishary;
    }

    return BuiltInAudioSource(
      id: id,
      displayName: json['displayName'] as String? ?? 'الشيخ مشاري راشد العفاسي',
      assetPath: json['assetPath'] as String? ?? 'assets/sounds/adhan.mp3',
      fajrAssetPath: json['fajrAssetPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuiltInAudioSource &&
          id == other.id &&
          displayName == other.displayName &&
          assetPath == other.assetPath &&
          fajrAssetPath == other.fajrAssetPath;

  @override
  int get hashCode => Object.hash(id, displayName, assetPath, fajrAssetPath);

  @override
  String toString() =>
      'BuiltInAudioSource(id: $id, displayName: $displayName, assetPath: $assetPath, fajrAssetPath: $fajrAssetPath)';
}

/// User-imported custom audio source stored in private app storage.
@immutable
class CustomAudioSource extends AudioSourceConfig {
  final String localRelativePath;
  final String? iqamaLocalRelativePath;
  final String originalFileName;
  final int fileSize;

  const CustomAudioSource({
    required super.id,
    required super.displayName,
    required this.localRelativePath,
    this.iqamaLocalRelativePath,
    required this.originalFileName,
    required this.fileSize,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'custom',
        'id': id,
        'displayName': displayName,
        'localRelativePath': localRelativePath,
        if (iqamaLocalRelativePath != null)
          'iqamaLocalRelativePath': iqamaLocalRelativePath,
        'originalFileName': originalFileName,
        'fileSize': fileSize,
      };

  factory CustomAudioSource.fromJson(Map<String, dynamic> json) {
    final localPath = json['localRelativePath'] as String?;
    if (localPath == null || localPath.isEmpty) {
      throw const FormatException('Missing localRelativePath for custom audio source');
    }
    return CustomAudioSource(
      id: json['id'] as String? ?? 'custom:${DateTime.now().millisecondsSinceEpoch}',
      displayName: json['displayName'] as String? ?? 'صوت مخصص',
      localRelativePath: localPath,
      iqamaLocalRelativePath: json['iqamaLocalRelativePath'] as String?,
      originalFileName: json['originalFileName'] as String? ?? 'custom_audio',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomAudioSource &&
          id == other.id &&
          displayName == other.displayName &&
          localRelativePath == other.localRelativePath &&
          iqamaLocalRelativePath == other.iqamaLocalRelativePath &&
          originalFileName == other.originalFileName &&
          fileSize == other.fileSize;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        localRelativePath,
        iqamaLocalRelativePath,
        originalFileName,
        fileSize,
      );

  @override
  String toString() =>
      'CustomAudioSource(id: $id, displayName: $displayName, path: $localRelativePath, iqama: $iqamaLocalRelativePath, size: $fileSize)';
}

