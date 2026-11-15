import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Loads and parses the fixture JSON file.
Map<String, dynamic> _loadFixture() {
  final file = File('test/fixtures/adhan_catalog_v1_sample.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Returns a minimal valid catalog JSON map with [overrides] applied.
Map<String, dynamic> _minimalCatalog({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'schema_version': 1,
    'entries': <dynamic>[],
  };
  if (overrides != null) base.addAll(overrides);
  return base;
}

/// Returns a fully valid entry JSON map with optional [overrides].
Map<String, dynamic> _validEntryJson({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'id': 'remote:test_general',
    'sheikh_name': 'شيخ اختباري',
    'audio_type': 'general',
    'display_name': 'أذان - شيخ اختباري',
    'duration_seconds': 60,
    'object_key': 'audio/test_general.mp3',
    'file_size_bytes': 960000,
    'sha256': 'a' * 64,
  };
  if (overrides != null) base.addAll(overrides);
  return base;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AdhanCatalogEntry — validation contract', () {
    test('valid entry passes all constraints', () {
      final entry = AdhanCatalogEntry.fromJson(_validEntryJson());
      expect(entry, isNotNull);
      expect(entry!.isValid, isTrue);
      expect(entry.validationErrors, isEmpty);
    });

    test('id must start with "remote:" prefix', () {
      final entry = AdhanCatalogEntry.fromJson(
        _validEntryJson(overrides: {'id': 'builtIn:something'}),
      );
      expect(entry, isNull, reason: 'id without "remote:" prefix must be rejected');
    });

    test('empty id is rejected', () {
      final entry = AdhanCatalogEntry.fromJson(
        _validEntryJson(overrides: {'id': ''}),
      );
      expect(entry, isNull);
    });

    test('sha256 must be exactly 64 lowercase hex characters', () {
      // Too short
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'sha256': 'a' * 63})),
        isNull,
      );
      // Too long
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'sha256': 'a' * 65})),
        isNull,
      );
      // Uppercase rejected
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'sha256': 'A' * 64})),
        isNull,
      );
      // Non-hex chars rejected
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'sha256': 'g' * 64})),
        isNull,
      );
      // Valid 64-char lowercase hex accepted
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'sha256': 'f' * 64})),
        isNotNull,
      );
    });

    test('objectKey must not contain path traversal sequences', () {
      expect(
        AdhanCatalogEntry.fromJson(
          _validEntryJson(overrides: {'object_key': '../secrets/key.mp3'}),
        ),
        isNull,
        reason: 'path traversal in objectKey must be rejected',
      );
      expect(
        AdhanCatalogEntry.fromJson(
          _validEntryJson(overrides: {'object_key': 'audio/../../etc/passwd'}),
        ),
        isNull,
      );
    });

    test('empty objectKey is rejected', () {
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'object_key': ''})),
        isNull,
      );
    });

    test('fileSizeBytes boundaries: <= 0 and > 30MB are rejected, exactly 30MB accepted', () {
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'file_size_bytes': 0})),
        isNull,
      );
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'file_size_bytes': -1})),
        isNull,
      );
      // Exactly 30MB is accepted
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'file_size_bytes': 30 * 1024 * 1024})),
        isNotNull,
      );
      // > 30MB is rejected
      expect(
        AdhanCatalogEntry.fromJson(_validEntryJson(overrides: {'file_size_bytes': 30 * 1024 * 1024 + 1})),
        isNull,
      );
    });

    test('unknown audio_type causes entry to be silently skipped (returns null)', () {
      final entry = AdhanCatalogEntry.fromJson(
        _validEntryJson(overrides: {'audio_type': 'unknown_future_type'}),
      );
      expect(entry, isNull,
          reason: 'Unknown audio types must be ignored, not throw');
    });

    test('all three known audio_types are accepted', () {
      for (final type in ['general', 'fajr', 'iqama']) {
        final entry = AdhanCatalogEntry.fromJson(
          _validEntryJson(overrides: {'id': 'remote:test_$type', 'audio_type': type}),
        );
        expect(entry, isNotNull, reason: 'audio_type "$type" should be valid');
        expect(entry!.audioType.key, equals(type));
      }
    });

    test('validationErrors lists all constraint violations', () {
      // Craft an entry with multiple violations by bypassing fromJson
      const badEntry = AdhanCatalogEntry(
        id: 'builtIn:wrong', // wrong prefix
        sheikhName: 'x',
        audioType: AdhanAudioType.general,
        displayName: 'x',
        durationSeconds: 0,
        objectKey: '../traversal', // path traversal
        fileSizeBytes: -5, // negative
        sha256: 'tooshort', // wrong length
      );
      final errors = badEntry.validationErrors;
      expect(errors.length, greaterThanOrEqualTo(3));
      expect(errors.any((e) => e.contains('remote:')), isTrue);
      expect(errors.any((e) => e.contains('path traversal')), isTrue);
      expect(errors.any((e) => e.contains('sha256')), isTrue);
    });

    test('malformed JSON does not throw — returns null', () {
      expect(
        AdhanCatalogEntry.fromJson({'id': 123, 'audio_type': 42}),
        isNull,
        reason: 'Malformed fields must not throw',
      );
    });

    test('extra unknown fields are ignored (forward compatibility)', () {
      final entry = AdhanCatalogEntry.fromJson({
        ..._validEntryJson(),
        'future_field_v2': 'some_value',
        'another_new_field': 42,
      });
      expect(entry, isNotNull,
          reason: 'Unknown future fields must not cause rejection');
    });

    test('previewOffsetSeconds defaults to 0 when absent', () {
      final json = _validEntryJson()..remove('preview_offset_seconds');
      final entry = AdhanCatalogEntry.fromJson(json);
      expect(entry, isNotNull);
      expect(entry!.previewOffsetSeconds, equals(0));
    });

    test('description is optional', () {
      final json = _validEntryJson()..remove('description');
      final entry = AdhanCatalogEntry.fromJson(json);
      expect(entry, isNotNull);
      expect(entry!.description, isNull);
    });

    test('sha256 is preserved exactly', () {
      const hash = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      final entry = AdhanCatalogEntry.fromJson(
        _validEntryJson(overrides: {'sha256': hash}),
      );
      expect(entry, isNotNull);
      expect(entry!.sha256, equals(hash));
    });

    test('toJson → fromJson round-trip preserves all fields', () {
      const original = AdhanCatalogEntry(
        id: 'remote:roundtrip_test',
        sheikhName: 'الشيخ الاختباري',
        audioType: AdhanAudioType.fajr,
        displayName: 'أذان الفجر - اختبار',
        description: 'وصف اختباري',
        durationSeconds: 75,
        objectKey: 'audio/roundtrip.mp3',
        fileSizeBytes: 1200000,
        sha256: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
        previewOffsetSeconds: 5,
      );

      final json = original.toJson();
      final parsed = AdhanCatalogEntry.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals(original.id));
      expect(parsed.sheikhName, equals(original.sheikhName));
      expect(parsed.audioType, equals(original.audioType));
      expect(parsed.displayName, equals(original.displayName));
      expect(parsed.description, equals(original.description));
      expect(parsed.durationSeconds, equals(original.durationSeconds));
      expect(parsed.objectKey, equals(original.objectKey));
      expect(parsed.fileSizeBytes, equals(original.fileSizeBytes));
      expect(parsed.sha256, equals(original.sha256));
      expect(parsed.previewOffsetSeconds, equals(original.previewOffsetSeconds));
    });
  });

  // -------------------------------------------------------------------------

  group('AdhanCatalog — schema version contract', () {
    test('schema_version 1 is accepted', () {
      expect(
        () => AdhanCatalog.fromJson(_minimalCatalog()),
        returnsNormally,
      );
    });

    test('missing schema_version throws AdhanCatalogParseException', () {
      final json = _minimalCatalog();
      json.remove('schema_version');
      expect(
        () => AdhanCatalog.fromJson(json),
        throwsA(isA<AdhanCatalogParseException>().having(
          (e) => e.message,
          'message',
          contains('schema_version'),
        )),
      );
    });

    test('schema_version 0 throws AdhanCatalogParseException (unsupported)', () {
      expect(
        () => AdhanCatalog.fromJson(_minimalCatalog(overrides: {'schema_version': 0})),
        throwsA(isA<AdhanCatalogParseException>()),
      );
    });

    test('schema_version 2 throws AdhanCatalogParseException (future, unsupported)', () {
      expect(
        () => AdhanCatalog.fromJson(_minimalCatalog(overrides: {'schema_version': 2})),
        throwsA(isA<AdhanCatalogParseException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported catalog schema version'),
        )),
      );
    });

    test('schema_version as string throws AdhanCatalogParseException', () {
      expect(
        () => AdhanCatalog.fromJson(_minimalCatalog(overrides: {'schema_version': '1'})),
        throwsA(isA<AdhanCatalogParseException>().having(
          (e) => e.message,
          'message',
          contains('must be an integer'),
        )),
      );
    });

    test('missing entries field throws AdhanCatalogParseException', () {
      final json = _minimalCatalog();
      json.remove('entries');
      expect(
        () => AdhanCatalog.fromJson(json),
        throwsA(isA<AdhanCatalogParseException>().having(
          (e) => e.message,
          'message',
          contains('entries'),
        )),
      );
    });

    test('entries as non-array throws AdhanCatalogParseException', () {
      expect(
        () => AdhanCatalog.fromJson(_minimalCatalog(overrides: {'entries': 'not_an_array'})),
        throwsA(isA<AdhanCatalogParseException>()),
      );
    });

    test('empty entries array is accepted — returns catalog with 0 entries', () {
      final catalog = AdhanCatalog.fromJson(_minimalCatalog());
      expect(catalog.entries, isEmpty);
    });

    test('generated_at is optional', () {
      final catalog = AdhanCatalog.fromJson(_minimalCatalog());
      expect(catalog.generatedAt, isNull);
    });

    test('generated_at is preserved when present', () {
      const ts = '2026-11-13T00:00:00Z';
      final catalog = AdhanCatalog.fromJson(
        _minimalCatalog(overrides: {'generated_at': ts}),
      );
      expect(catalog.generatedAt, equals(ts));
    });

    test('extra unknown top-level fields are ignored', () {
      final json = _minimalCatalog(overrides: {
        'future_v2_field': 'value',
        'experimental': true,
      });
      expect(() => AdhanCatalog.fromJson(json), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------

  group('AdhanCatalog — partial validity (mixed entry list)', () {
    test('invalid entries are silently dropped; valid entries are preserved', () {
      final json = _minimalCatalog(overrides: {
        'entries': [
          _validEntryJson(overrides: {'id': 'remote:valid_1'}),
          {'id': 'invalid_no_prefix', 'audio_type': 'general'}, // invalid id prefix
          _validEntryJson(overrides: {
            'id': 'remote:future_type',
            'audio_type': 'future_unknown_type',
          }), // unknown type — skipped
          _validEntryJson(overrides: {'id': 'remote:valid_2'}),
        ],
      });

      final catalog = AdhanCatalog.fromJson(json);
      expect(catalog.entries.length, equals(2),
          reason: 'Only the 2 valid entries should survive');
      expect(catalog.entries.map((e) => e.id).toList(),
          containsAll(['remote:valid_1', 'remote:valid_2']));
    });

    test('catalog with all invalid entries has 0 entries — does not throw', () {
      final json = _minimalCatalog(overrides: {
        'entries': [
          {'id': 'bad', 'audio_type': 'general'},
          {'id': 'remote:no_sha256'},
        ],
      });
      final catalog = AdhanCatalog.fromJson(json);
      expect(catalog.entries, isEmpty);
    });

    test('non-object elements in entries array are silently skipped', () {
      final json = _minimalCatalog(overrides: {
        'entries': [
          'a_string',
          42,
          null,
          _validEntryJson(),
        ],
      });
      final catalog = AdhanCatalog.fromJson(json);
      expect(catalog.entries.length, equals(1));
    });
  });

  // -------------------------------------------------------------------------

  group('AdhanCatalog — filter helpers', () {
    late AdhanCatalog catalog;

    setUp(() {
      catalog = AdhanCatalog.fromJson(_minimalCatalog(overrides: {
        'entries': [
          _validEntryJson(overrides: {'id': 'remote:g1', 'audio_type': 'general'}),
          _validEntryJson(overrides: {'id': 'remote:g2', 'audio_type': 'general'}),
          _validEntryJson(overrides: {'id': 'remote:f1', 'audio_type': 'fajr'}),
          _validEntryJson(overrides: {'id': 'remote:i1', 'audio_type': 'iqama'}),
        ],
      }));
    });

    test('generalEntries returns only general type', () {
      expect(catalog.generalEntries.length, equals(2));
      expect(catalog.generalEntries.every((e) => e.audioType == AdhanAudioType.general), isTrue);
    });

    test('fajrEntries returns only fajr type', () {
      expect(catalog.fajrEntries.length, equals(1));
      expect(catalog.fajrEntries.first.id, equals('remote:f1'));
    });

    test('iqamaEntries returns only iqama type', () {
      expect(catalog.iqamaEntries.length, equals(1));
      expect(catalog.iqamaEntries.first.id, equals('remote:i1'));
    });

    test('findById returns correct entry', () {
      final entry = catalog.findById('remote:f1');
      expect(entry, isNotNull);
      expect(entry!.audioType, equals(AdhanAudioType.fajr));
    });

    test('findById returns null for unknown id', () {
      expect(catalog.findById('remote:nonexistent'), isNull);
    });
  });

  // -------------------------------------------------------------------------

  group('AdhanCatalog — toJson/fromJson round-trip', () {
    test('round-trip preserves schema_version and all entries', () {
      final original = AdhanCatalog.fromJson(_loadFixture());
      final json = original.toJson();
      final reparsed = AdhanCatalog.fromJson(json);

      expect(reparsed.schemaVersion, equals(original.schemaVersion));
      expect(reparsed.entries.length, equals(original.entries.length));
      for (int i = 0; i < original.entries.length; i++) {
        expect(reparsed.entries[i], equals(original.entries[i]));
      }
    });
  });

  // -------------------------------------------------------------------------

  group('Sample fixture — integration parse', () {
    late Map<String, dynamic> fixtureJson;
    late AdhanCatalog catalog;

    setUp(() {
      fixtureJson = _loadFixture();
      catalog = AdhanCatalog.fromJson(fixtureJson);
    });

    test('fixture parses without throwing', () {
      expect(catalog.schemaVersion, equals(1));
    });

    test('fixture contains 4 entries (2 general, 1 fajr, 1 iqama)', () {
      expect(catalog.entries.length, equals(4));
      expect(catalog.generalEntries.length, equals(2));
      expect(catalog.fajrEntries.length, equals(1));
      expect(catalog.iqamaEntries.length, equals(1));
    });

    test('all fixture entries pass isValid', () {
      for (final entry in catalog.entries) {
        expect(entry.isValid, isTrue, reason: '${entry.id} should be valid');
      }
    });

    test('fixture sha256 fields are preserved exactly', () {
      final rawEntries = fixtureJson['entries'] as List;
      for (int i = 0; i < rawEntries.length; i++) {
        final raw = rawEntries[i] as Map<String, dynamic>;
        expect(catalog.entries[i].sha256, equals(raw['sha256']));
      }
    });

    test('fixture entry ids all start with "remote:"', () {
      for (final entry in catalog.entries) {
        expect(entry.id, startsWith('remote:'));
      }
    });

    test('fixture object keys contain no path traversal', () {
      for (final entry in catalog.entries) {
        expect(entry.objectKey, isNot(contains('..')));
      }
    });

    test('fajr entry has correct audio type label', () {
      final fajr = catalog.fajrEntries.first;
      expect(fajr.audioType.arabicLabel, equals('أذان الفجر'));
    });
  });

  // -------------------------------------------------------------------------

  group('CatalogConfig — URL resolution', () {
    test('kCatalogBaseUrlUndefined is returned when dart-define is absent', () {
      // In test environment, CATALOG_BASE_URL is never injected
      expect(CatalogConfig.baseUrl, equals(kCatalogBaseUrlUndefined));
    });

    test('isConfigured is false in test environment', () {
      expect(CatalogConfig.isConfigured, isFalse);
    });

    test('audioUrl returns null when base URL is unconfigured', () {
      expect(CatalogConfig.audioUrl('audio/test.mp3'), isNull);
    });

    test('audioUrl returns null for empty objectKey', () {
      expect(CatalogConfig.audioUrl(''), isNull);
    });

    test('audioUrl returns null for objectKey with path traversal', () {
      expect(CatalogConfig.audioUrl('../secrets.mp3'), isNull);
      expect(CatalogConfig.audioUrl('audio/../../etc.mp3'), isNull);
    });

    test('audioUrl deduplicates redundant base directory in objectKey', () {
      final url = CatalogConfig.audioUrl(
        'catalog/audio/mishary.mp3',
        customBaseUrl: 'https://cdn.example.com/catalog',
      );
      expect(url, equals('https://cdn.example.com/catalog/audio/mishary.mp3'));
    });

    test('audioUrl deduplicates base directory when baseUrl ends with catalog.json', () {
      final url = CatalogConfig.audioUrl(
        'catalog/audio/mishary.mp3',
        customBaseUrl: 'https://cdn.example.com/catalog/catalog.json',
      );
      expect(url, equals('https://cdn.example.com/catalog/audio/mishary.mp3'));
    });

    test('audioUrl preserves objectKey when baseUrl is domain root', () {
      final url = CatalogConfig.audioUrl(
        'catalog/audio/mishary.mp3',
        customBaseUrl: 'https://cdn.example.com',
      );
      expect(url, equals('https://cdn.example.com/catalog/audio/mishary.mp3'));
    });

    test('catalogJsonUrl includes correct object key suffix', () {
      // Even unconfigured, the suffix must be correct
      expect(CatalogConfig.catalogJsonUrl, contains(kCatalogJsonObjectKey));
    });

    test('kCatalogCacheTtl is 24 hours', () {
      expect(kCatalogCacheTtl, equals(const Duration(hours: 24)));
    });

    test('kCatalogJsonMaxBytes is 1 MB', () {
      expect(kCatalogJsonMaxBytes, equals(1 * 1024 * 1024));
    });

    test('kRemoteAudioMaxBytes is 30 MB', () {
      expect(kRemoteAudioMaxBytes, equals(30 * 1024 * 1024));
    });
  });

  // -------------------------------------------------------------------------

  group('AdhanAudioType — serialization', () {
    test('fromKey returns correct enum for all known values', () {
      expect(AdhanAudioType.fromKey('general'), equals(AdhanAudioType.general));
      expect(AdhanAudioType.fromKey('fajr'), equals(AdhanAudioType.fajr));
      expect(AdhanAudioType.fromKey('iqama'), equals(AdhanAudioType.iqama));
    });

    test('fromKey returns null for unknown values', () {
      expect(AdhanAudioType.fromKey('unknown'), isNull);
      expect(AdhanAudioType.fromKey(''), isNull);
      expect(AdhanAudioType.fromKey(null), isNull);
    });

    test('fromKey is case-insensitive', () {
      expect(AdhanAudioType.fromKey('GENERAL'), equals(AdhanAudioType.general));
      expect(AdhanAudioType.fromKey('Fajr'), equals(AdhanAudioType.fajr));
      expect(AdhanAudioType.fromKey('IQAMA'), equals(AdhanAudioType.iqama));
    });

    test('key round-trips through fromKey', () {
      for (final type in AdhanAudioType.values) {
        expect(AdhanAudioType.fromKey(type.key), equals(type));
      }
    });

    test('all types have non-empty arabicLabel', () {
      for (final type in AdhanAudioType.values) {
        expect(type.arabicLabel, isNotEmpty);
      }
    });
  });
}

