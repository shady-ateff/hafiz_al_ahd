import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';

/// Developer-only configuration constants for Catalog Draft Management.
///
/// These constants and paths are used exclusively by developer tools and
/// are completely eliminated in Release builds.
abstract final class CatalogDeveloperConfig {
  CatalogDeveloperConfig._();

  /// Standard file name for the local catalog draft JSON file.
  static const String draftFileName = 'developer_catalog_draft.json';

  /// Temporary file name used for atomic persistence of the draft.
  static const String draftTempFileName = 'developer_catalog_draft.json.tmp';

  /// Maximum allowed draft JSON file size (2 MB).
  static const int maxDraftSizeBytes = 2 * 1024 * 1024;

  /// Allowed audio extensions for catalog entries.
  static const Set<String> allowedAudioExtensions = {'.mp3', '.m4a', '.wav'};

  /// Allowed audio type wire keys.
  static const Set<String> allowedAudioTypeKeys = {'general', 'fajr', 'iqama'};

  /// Whether developer tools are active in the current build environment.
  static bool get isActive => isCatalogDeveloperToolsActive;

  /// Pure helper to evaluate developer tools activation flag with explicit inputs.
  /// Used for deterministic unit testing of release isolation logic.
  @visibleForTesting
  static bool computeIsActive({
    required bool isDebug,
    required bool isFlagEnabled,
  }) {
    return isDebug && isFlagEnabled;
  }
}

