import 'package:hafiz_al_ahd/features/notifications/developer/domain/entities/catalog_validation_error.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';

/// Base exception for catalog draft operations.
abstract class CatalogDraftException implements Exception {
  final String message;
  const CatalogDraftException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an existing draft file on disk contains corrupted JSON.
class CatalogDraftCorruptException extends CatalogDraftException {
  const CatalogDraftCorruptException(super.message);
}

/// Thrown when disk I/O or atomic rename fails during draft persistence.
class CatalogDraftStorageException extends CatalogDraftException {
  const CatalogDraftStorageException(super.message);
}

/// Thrown when [resetDraftToLive] is called without explicit user confirmation.
class CatalogDraftResetRejectedException extends CatalogDraftException {
  const CatalogDraftResetRejectedException(super.message);
}

/// Thrown when neither live nor cached valid catalog is available to seed the reset.
class CatalogDraftResetUnavailableException extends CatalogDraftException {
  const CatalogDraftResetUnavailableException(super.message);
}

/// Thrown when trying to export a draft that contains schema or contract validation errors.
class CatalogDraftExportValidationException extends CatalogDraftException {
  final List<CatalogValidationError> errors;

  const CatalogDraftExportValidationException(this.errors)
      : super('لا يمكن تصدير مسودة الكتالوج لأنها تحتوي على أخطاء في المخطط.');
}

/// Contract for managing developer-only local catalog drafts.
abstract interface class CatalogDraftManagerService {
  /// Loads the persisted draft from disk, or returns `null` if no draft file exists yet.
  ///
  /// Throws [CatalogDraftCorruptException] if the file exists but contains invalid JSON.
  Future<AdhanCatalog?> loadDraft();

  /// Persists [draft] atomically using temporary staging and atomic renaming.
  ///
  /// Throws [CatalogDraftStorageException] if atomic write or rename fails.
  Future<void> saveDraft(AdhanCatalog draft);

  /// Resets the draft from the live catalog (or cached fallback).
  ///
  /// Safety Guarantees:
  /// - Requires [confirmReset] == true to prevent accidental data loss.
  /// - Verifies that the live catalog is structurally valid before using as seed.
  /// - Falls back to the cached catalog if network fails.
  /// - If neither live nor cached catalog is available, rejects the reset without
  ///   modifying or deleting the existing draft.
  Future<AdhanCatalog> resetDraftToLive({required bool confirmReset});

  /// Formats and exports the draft into a pretty-printed JSON string.
  ///
  /// Throws [CatalogDraftExportValidationException] if the draft is not 100% valid.
  String exportDraftJson(AdhanCatalog draft);

  /// Deletes the draft and any dangling temporary files from disk.
  Future<void> deleteDraft();
}

