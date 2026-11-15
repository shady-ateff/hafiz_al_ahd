import 'package:flutter/foundation.dart';

/// Represents a validation error found in a catalog draft or JSON payload.
@immutable
class CatalogValidationError {
  /// Name or path of the field that failed validation (e.g. `'schema_version'`, `'entries[0].sha256'`).
  final String field;

  /// User-friendly, localized description of the error in Arabic.
  final String message;

  /// Index of the entry in the `entries` array, if this error pertains to a specific entry.
  final int? entryIndex;

  /// Unique identifier of the entry, if available.
  final String? entryId;

  const CatalogValidationError({
    required this.field,
    required this.message,
    this.entryIndex,
    this.entryId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogValidationError &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          message == other.message &&
          entryIndex == other.entryIndex &&
          entryId == other.entryId;

  @override
  int get hashCode => Object.hash(field, message, entryIndex, entryId);

  @override
  String toString() {
    final target = entryIndex != null
        ? 'Entry #$entryIndex${entryId != null ? ' ($entryId)' : ''}'
        : 'Catalog';
    return 'CatalogValidationError($target, field: $field, message: $message)';
  }
}

