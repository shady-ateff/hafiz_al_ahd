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

  /// Default built-in audio source fallback.
  static BuiltInAudioSource defaultBuiltInFallback({bool isFajr = false}) => isFajr
      ? const BuiltInAudioSource(
          id: 'builtIn:default_fajr',
          displayName: 'أذان الفجر (الافتراضي)',
          assetPath: 'assets/sounds/fajr_azan.mp3',
        )
      : const BuiltInAudioSource(
          id: 'builtIn:default_general',
          displayName: 'الأذان العام (الافتراضي)',
          assetPath: 'assets/sounds/adhan.mp3',
        );
}

/// Built-in app asset audio source.
@immutable
class BuiltInAudioSource extends AudioSourceConfig {
  final String assetPath;

  const BuiltInAudioSource({
    required super.id,
    required super.displayName,
    required this.assetPath,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'builtIn',
        'id': id,
        'displayName': displayName,
        'assetPath': assetPath,
      };

  factory BuiltInAudioSource.fromJson(Map<String, dynamic> json) {
    return BuiltInAudioSource(
      id: json['id'] as String? ?? 'builtIn:default_general',
      displayName: json['displayName'] as String? ?? 'الأذان العام (الافتراضي)',
      assetPath: json['assetPath'] as String? ?? 'assets/sounds/adhan.mp3',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuiltInAudioSource &&
          id == other.id &&
          displayName == other.displayName &&
          assetPath == other.assetPath;

  @override
  int get hashCode => Object.hash(id, displayName, assetPath);

  @override
  String toString() => 'BuiltInAudioSource(id: $id, displayName: $displayName, assetPath: $assetPath)';
}

/// User-imported custom audio source stored in private app storage.
@immutable
class CustomAudioSource extends AudioSourceConfig {
  final String localRelativePath;
  final String originalFileName;
  final int fileSize;

  const CustomAudioSource({
    required super.id,
    required super.displayName,
    required this.localRelativePath,
    required this.originalFileName,
    required this.fileSize,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'custom',
        'id': id,
        'displayName': displayName,
        'localRelativePath': localRelativePath,
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
          originalFileName == other.originalFileName &&
          fileSize == other.fileSize;

  @override
  int get hashCode => Object.hash(id, displayName, localRelativePath, originalFileName, fileSize);

  @override
  String toString() =>
      'CustomAudioSource(id: $id, displayName: $displayName, path: $localRelativePath, original: $originalFileName, size: $fileSize)';
}

