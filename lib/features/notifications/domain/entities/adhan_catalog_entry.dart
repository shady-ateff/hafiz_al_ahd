import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';

/// The intended use context of a remote adhan audio entry.
///
/// - [general]: Suitable for all 5 prayers (non-Fajr context).
/// - [fajr]: Fajr-specific adhan, includes "الصلاة خير من النوم".
/// - [iqama]: Iqama audio (shorter call to begin prayer).
enum AdhanAudioType {
  general,
  fajr,
  iqama;

  /// JSON wire value.
  String get key => name;

  /// Arabic display label.
  String get arabicLabel {
    switch (this) {
      case AdhanAudioType.general:
        return 'أذان عام';
      case AdhanAudioType.fajr:
        return 'أذان الفجر';
      case AdhanAudioType.iqama:
        return 'إقامة';
    }
  }

  /// Safe deserialization. Unknown values return null — callers must skip them
  /// rather than failing the whole catalog parse.
  static AdhanAudioType? fromKey(String? key) {
    if (key == null) return null;
    for (final type in AdhanAudioType.values) {
      if (type.name == key.trim().toLowerCase()) return type;
    }
    return null;
  }
}

/// Companion Iqama audio information optionally attached to a general adhan entry.
@immutable
class AdhanCatalogIqamaInfo {
  /// R2 object key for the iqama audio file.
  final String objectKey;

  /// Expected file size in bytes.
  final int fileSizeBytes;

  /// Expected SHA-256 hex digest (64 lowercase hex chars).
  final String sha256;

  /// Playback duration in seconds.
  final int durationSeconds;

  const AdhanCatalogIqamaInfo({
    required this.objectKey,
    required this.fileSizeBytes,
    required this.sha256,
    required this.durationSeconds,
  });

  /// Returns true if this iqama info satisfies all constraints.
  bool get isValid {
    if (objectKey.isEmpty || objectKey.contains('..')) return false;
    if (fileSizeBytes <= 0 || fileSizeBytes > kRemoteAudioMaxBytes) return false;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) return false;
    return true;
  }

  static AdhanCatalogIqamaInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final info = AdhanCatalogIqamaInfo(
        objectKey: json['object_key'] as String? ?? '',
        fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      );
      return info.isValid ? info : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'object_key': objectKey,
        'file_size_bytes': fileSizeBytes,
        'sha256': sha256,
        'duration_seconds': durationSeconds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanCatalogIqamaInfo &&
          objectKey == other.objectKey &&
          sha256 == other.sha256 &&
          fileSizeBytes == other.fileSizeBytes &&
          durationSeconds == other.durationSeconds;

  @override
  int get hashCode => Object.hash(objectKey, sha256, fileSizeBytes, durationSeconds);
}

/// A single entry in the remote adhan audio catalog.
///
/// Each entry represents one audio file hosted on Cloudflare R2. After the
/// user downloads a [AdhanCatalogEntry], it is stored locally via
/// [CustomAudioStorageService] and surfaced as a [CustomAudioSource].
///
/// ## Validation contract
/// An entry is **valid** if and only if:
/// - [id] is non-empty and starts with `"remote:"`.
/// - [objectKey] is non-empty and contains no path traversal sequences (`..`).
/// - [sha256] is exactly 64 lowercase hexadecimal characters.
/// - [fileSizeBytes] is > 0.
/// - [audioType] is a recognised [AdhanAudioType] value.
@immutable
class AdhanCatalogEntry {
  /// Stable unique identifier. Format: `remote:<slug>`.
  /// Example: `remote:mishary_alafasy_fajr`
  final String id;

  /// Sheikh / reciter name in Arabic.
  final String sheikhName;

  /// Intended audio use context.
  final AdhanAudioType audioType;

  /// User-facing display name in Arabic.
  final String displayName;

  /// Optional short description shown in the catalog UI.
  final String? description;

  /// Approximate playback duration in seconds (informational only).
  final int durationSeconds;

  /// R2 object key relative to the bucket root.
  /// Example: `audio/mishary_alafasy_fajr.mp3`
  final String objectKey;

  /// Expected file size in bytes — used for download progress and
  /// size validation before SHA-256 is verified.
  final int fileSizeBytes;

  /// Expected SHA-256 hex digest (64 lowercase hex chars) of the audio file
  /// at [objectKey]. **Must** be verified after download before the file is
  /// committed to local storage.
  final String sha256;

  /// Offset in seconds to begin the audio preview from (default: 0).
  final int previewOffsetSeconds;

  /// Optional companion Iqama audio information (for general adhan entries).
  final AdhanCatalogIqamaInfo? iqama;

  const AdhanCatalogEntry({
    required this.id,
    required this.sheikhName,
    required this.audioType,
    required this.displayName,
    this.description,
    required this.durationSeconds,
    required this.objectKey,
    required this.fileSizeBytes,
    required this.sha256,
    this.previewOffsetSeconds = 0,
    this.iqama,
  });

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns true if this entry satisfies all validity constraints.
  bool get isValid {
    if (id.isEmpty || !id.startsWith('remote:')) return false;
    if (objectKey.isEmpty || objectKey.contains('..')) return false;
    if (!_isValidSha256(sha256)) return false;
    if (fileSizeBytes <= 0 || fileSizeBytes > kRemoteAudioMaxBytes) return false;
    if (iqama != null && !iqama!.isValid) return false;
    return true;
  }

  /// Collects all constraint violations as human-readable strings.
  /// Returns an empty list if the entry is valid.
  List<String> get validationErrors {
    final errors = <String>[];
    if (id.isEmpty) {
      errors.add('id is empty');
    } else if (!id.startsWith('remote:')) {
      errors.add('id must start with "remote:" (got: "$id")');
    }
    if (objectKey.isEmpty) {
      errors.add('objectKey is empty');
    } else if (objectKey.contains('..')) {
      errors.add('objectKey contains path traversal sequence: "$objectKey"');
    }
    if (!_isValidSha256(sha256)) {
      errors.add('sha256 must be exactly 64 lowercase hex chars (got: "${sha256.length} chars")');
    }
    if (fileSizeBytes <= 0) {
      errors.add('fileSizeBytes must be > 0 (got: $fileSizeBytes)');
    } else if (fileSizeBytes > kRemoteAudioMaxBytes) {
      errors.add('fileSizeBytes must be <= $kRemoteAudioMaxBytes (got: $fileSizeBytes)');
    }
    if (iqama != null && !iqama!.isValid) {
      errors.add('iqama contains invalid metadata');
    }
    return errors;
  }

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  static bool _isValidSha256(String value) => _sha256Pattern.hasMatch(value);

  // ---------------------------------------------------------------------------
  // JSON serialization
  // ---------------------------------------------------------------------------

  /// Parses a single catalog entry from JSON.
  ///
  /// Returns null — without throwing — when:
  /// - [audioType] is unrecognised (forward-compatible: ignore unknown types).
  /// - Any required field is missing or malformed.
  /// - The entry fails [isValid].
  ///
  /// Callers must filter nulls from the resulting list.
  static AdhanCatalogEntry? fromJson(Map<String, dynamic> json) {
    try {
      final audioTypeKey = json['audio_type'] as String?;
      final audioType = AdhanAudioType.fromKey(audioTypeKey);
      if (audioType == null) return null; // unknown type — skip gracefully

      AdhanCatalogIqamaInfo? iqama;
      if (json.containsKey('iqama') && json['iqama'] != null) {
        if (json['iqama'] is! Map<String, dynamic>) return null;
        iqama = AdhanCatalogIqamaInfo.fromJson(json['iqama'] as Map<String, dynamic>);
        if (iqama == null) return null; // Invalid companion iqama rejects the entry
      }

      final entry = AdhanCatalogEntry(
        id: json['id'] as String? ?? '',
        sheikhName: json['sheikh_name'] as String? ?? '',
        audioType: audioType,
        displayName: json['display_name'] as String? ?? '',
        description: json['description'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        objectKey: json['object_key'] as String? ?? '',
        fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
        previewOffsetSeconds: (json['preview_offset_seconds'] as num?)?.toInt() ?? 0,
        iqama: iqama,
      );

      return entry.isValid ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sheikh_name': sheikhName,
        'audio_type': audioType.key,
        'display_name': displayName,
        if (description != null) 'description': description,
        'duration_seconds': durationSeconds,
        'object_key': objectKey,
        'file_size_bytes': fileSizeBytes,
        'sha256': sha256,
        if (previewOffsetSeconds != 0) 'preview_offset_seconds': previewOffsetSeconds,
        if (iqama != null) 'iqama': iqama!.toJson(),
      };

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanCatalogEntry &&
          id == other.id &&
          objectKey == other.objectKey &&
          sha256 == other.sha256 &&
          iqama == other.iqama;

  @override
  int get hashCode => Object.hash(id, objectKey, sha256, iqama);

  @override
  String toString() =>
      'AdhanCatalogEntry(id: $id, type: ${audioType.key}, objectKey: $objectKey)';
}

