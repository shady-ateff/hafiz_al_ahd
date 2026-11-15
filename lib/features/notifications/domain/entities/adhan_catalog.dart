import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';

/// The current and only supported catalog schema version.
const int kCatalogSchemaVersion = 1;

/// The parsed, validated remote adhan audio catalog.
///
/// ## Schema versioning
/// The catalog JSON carries a [schemaVersion] field. This model rejects any
/// catalog with an unsupported schema version rather than silently misreading
/// fields. Currently only version 1 is supported.
///
/// ## Partial validity
/// Individual entries that fail validation are silently dropped during parse
/// (see [AdhanCatalogEntry.fromJson]). A catalog with zero valid entries after
/// filtering is still considered a valid parse result — it is up to the UI to
/// show an appropriate empty state.
///
/// ## Forward compatibility
/// Unknown top-level fields are ignored. Unknown [AdhanAudioType] values in
/// individual entries cause those entries to be skipped.
@immutable
class AdhanCatalog {
  /// Must equal [kCatalogSchemaVersion] for this version of the app.
  final int schemaVersion;

  /// RFC 3339 timestamp string from the JSON (informational only).
  final String? generatedAt;

  /// All valid, parsed catalog entries. Invalid entries are excluded on parse.
  final List<AdhanCatalogEntry> entries;

  /// Total count of elements found in the raw "entries" array before validation.
  final int rawEntriesCount;

  /// Count of elements in the "entries" array that failed validation or had unknown types.
  final int droppedEntriesCount;

  const AdhanCatalog({
    required this.schemaVersion,
    this.generatedAt,
    required this.entries,
    this.rawEntriesCount = 0,
    this.droppedEntriesCount = 0,
  });

  // ---------------------------------------------------------------------------
  // Validation status
  // ---------------------------------------------------------------------------

  /// Whether the catalog was parsed with 100% valid entries and zero drops.
  bool get isFullyValid => rawEntriesCount > 0 && droppedEntriesCount == 0;

  /// Whether the catalog has at least one valid entry, but some invalid entries were dropped.
  bool get isPartiallyValid => entries.isNotEmpty && droppedEntriesCount > 0;

  /// Whether the catalog had an empty "entries" array.
  bool get isEmpty => rawEntriesCount == 0 && entries.isEmpty;

  /// Whether the raw "entries" array had items, but ALL of them were invalid/dropped.
  /// A completely corrupt catalog must NEVER overwrite a valid cached catalog.
  bool get isCompletelyCorrupt => rawEntriesCount > 0 && entries.isEmpty;

  // ---------------------------------------------------------------------------
  // Convenience filters
  // ---------------------------------------------------------------------------

  /// All entries suitable for Fajr prayer (audio_type == fajr).
  List<AdhanCatalogEntry> get fajrEntries =>
      entries.where((e) => e.audioType == AdhanAudioType.fajr).toList();

  /// All entries suitable for general (non-Fajr) prayers.
  List<AdhanCatalogEntry> get generalEntries =>
      entries.where((e) => e.audioType == AdhanAudioType.general).toList();

  /// All iqama entries.
  List<AdhanCatalogEntry> get iqamaEntries =>
      entries.where((e) => e.audioType == AdhanAudioType.iqama).toList();

  /// Returns the entry matching [id], or null if not found.
  AdhanCatalogEntry? findById(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // JSON parsing
  // ---------------------------------------------------------------------------

  /// Parses a full catalog JSON map.
  ///
  /// Throws [AdhanCatalogParseException] when:
  /// - [json] is null or not a [Map<String, dynamic>].
  /// - [schema_version] is missing, not an integer, or unsupported.
  ///
  /// Individual invalid/unknown entries are silently dropped (see
  /// [AdhanCatalogEntry.fromJson]).
  static AdhanCatalog fromJson(Map<String, dynamic> json) {
    // 1. Schema version — hard requirement
    final rawVersion = json['schema_version'];
    if (rawVersion == null) {
      throw const AdhanCatalogParseException(
        'Missing required field "schema_version"',
      );
    }
    if (rawVersion is! int) {
      throw AdhanCatalogParseException(
        '"schema_version" must be an integer (got: ${rawVersion.runtimeType})',
      );
    }
    if (rawVersion != kCatalogSchemaVersion) {
      throw AdhanCatalogParseException(
        'Unsupported catalog schema version: $rawVersion '
        '(supported: $kCatalogSchemaVersion)',
      );
    }

    // 2. Entries array — required, but allowed to be empty
    final rawEntries = json['entries'];
    if (rawEntries == null) {
      throw const AdhanCatalogParseException('Missing required field "entries"');
    }
    if (rawEntries is! List) {
      throw AdhanCatalogParseException(
        '"entries" must be a JSON array (got: ${rawEntries.runtimeType})',
      );
    }

    // 3. Parse individual entries — count valid and dropped items
    final rawEntriesCount = rawEntries.length;
    final entries = <AdhanCatalogEntry>[];
    int droppedEntriesCount = 0;

    for (final element in rawEntries) {
      if (element is Map<String, dynamic>) {
        final parsed = AdhanCatalogEntry.fromJson(element);
        if (parsed != null) {
          entries.add(parsed);
        } else {
          droppedEntriesCount++;
        }
      } else {
        droppedEntriesCount++;
      }
    }

    return AdhanCatalog(
      schemaVersion: rawVersion,
      generatedAt: json['generated_at'] as String?,
      entries: entries,
      rawEntriesCount: rawEntriesCount,
      droppedEntriesCount: droppedEntriesCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        if (generatedAt != null) 'generated_at': generatedAt,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanCatalog &&
          schemaVersion == other.schemaVersion &&
          generatedAt == other.generatedAt &&
          entries.length == other.entries.length &&
          _entriesEqual(entries, other.entries);

  static bool _entriesEqual(
    List<AdhanCatalogEntry> a,
    List<AdhanCatalogEntry> b,
  ) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, generatedAt, Object.hashAll(entries));

  @override
  String toString() =>
      'AdhanCatalog(v$schemaVersion, ${entries.length} entries, generatedAt: $generatedAt)';
}

/// Thrown by [AdhanCatalog.fromJson] when the catalog JSON is structurally invalid.
///
/// Individual entry parse failures do NOT throw — they silently produce null
/// and are filtered. This exception covers catalog-level structural problems
/// (missing schema_version, unsupported version, non-array entries field).
class AdhanCatalogParseException implements Exception {
  final String message;

  const AdhanCatalogParseException(this.message);

  @override
  String toString() => 'AdhanCatalogParseException: $message';
}

