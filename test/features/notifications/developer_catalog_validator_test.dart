import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';

void main() {
  const validator = AdhanCatalogValidator();

  const validSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Map<String, dynamic> createValidEntryJson({
    String id = 'remote:test_sheikh_fajr',
    String sheikhName = 'الشيخ مشاري راشد العفاسي',
    String audioType = 'fajr',
    String displayName = 'أذان الفجر بصوت الشيخ مشاري',
    int durationSeconds = 180,
    String objectKey = 'audio/mishary_fajr.mp3',
    int fileSizeBytes = 2500000,
    String sha256 = validSha256,
    int previewOffsetSeconds = 15,
  }) {
    return {
      'id': id,
      'sheikh_name': sheikhName,
      'audio_type': audioType,
      'display_name': displayName,
      'duration_seconds': durationSeconds,
      'object_key': objectKey,
      'file_size_bytes': fileSizeBytes,
      'sha256': sha256,
      'preview_offset_seconds': previewOffsetSeconds,
    };
  }

  Map<String, dynamic> createValidCatalogJson({
    int schemaVersion = 1,
    String generatedAt = '2026-11-13T12:00:00Z',
    List<Map<String, dynamic>>? entries,
  }) {
    return {
      'schema_version': schemaVersion,
      'generated_at': generatedAt,
      'entries': entries ?? [createValidEntryJson()],
    };
  }

  group('AdhanCatalogValidator - Schema & Top-Level Constraints', () {
    test('Valid catalog JSON returns zero validation errors', () {
      final json = createValidCatalogJson();
      final errors = validator.validateJson(json);
      expect(errors, isEmpty);
    });

    test('Valid in-memory AdhanCatalog returns zero validation errors', () {
      final entry = AdhanCatalogEntry(
        id: 'remote:mishary_fajr',
        sheikhName: 'مشاري العفاسي',
        audioType: AdhanAudioType.fajr,
        displayName: 'أذان الفجر',
        durationSeconds: 150,
        objectKey: 'audio/mishary_fajr.mp3',
        fileSizeBytes: 2000000,
        sha256: validSha256,
      );
      final catalog = AdhanCatalog(
        schemaVersion: 1,
        generatedAt: '2026-11-13T12:00:00Z',
        entries: [entry],
      );

      final errors = validator.validateCatalog(catalog);
      expect(errors, isEmpty);
    });

    test('Missing schema_version flags error', () {
      final json = createValidCatalogJson()..remove('schema_version');
      final errors = validator.validateJson(json);
      expect(errors.any((e) => e.field == 'schema_version'), isTrue);
    });

    test('Non-integer schema_version flags error', () {
      final json = createValidCatalogJson(schemaVersion: 1)..['schema_version'] = '1';
      final errors = validator.validateJson(json);
      expect(errors.any((e) => e.field == 'schema_version'), isTrue);
    });

    test('Unsupported schema_version (e.g. 2) flags error', () {
      final json = createValidCatalogJson(schemaVersion: 2);
      final errors = validator.validateJson(json);
      expect(errors.any((e) => e.field == 'schema_version'), isTrue);
      expect(errors.firstWhere((e) => e.field == 'schema_version').message, contains('غير مدعوم'));
    });

    test('Invalid UTC timestamp flags error', () {
      // Non-UTC timestamp (missing Z or offset)
      final jsonNoUtc = createValidCatalogJson(generatedAt: '2026-11-13T12:00:00');
      final errorsNoUtc = validator.validateJson(jsonNoUtc);
      expect(errorsNoUtc.any((e) => e.field == 'generated_at'), isTrue);

      // Malformed date
      final jsonMalformed = createValidCatalogJson(generatedAt: 'not-a-date');
      final errorsMalformed = validator.validateJson(jsonMalformed);
      expect(errorsMalformed.any((e) => e.field == 'generated_at'), isTrue);
    });

    test('Missing or non-list entries array flags error', () {
      final jsonNoEntries = createValidCatalogJson()..remove('entries');
      final errorsNoEntries = validator.validateJson(jsonNoEntries);
      expect(errorsNoEntries.any((e) => e.field == 'entries'), isTrue);

      final jsonNotList = createValidCatalogJson()..['entries'] = 'not-a-list';
      final errorsNotList = validator.validateJson(jsonNotList);
      expect(errorsNotList.any((e) => e.field == 'entries'), isTrue);
    });
  });

  group('AdhanCatalogValidator - Entry Level Constraints', () {
    test('Empty required strings (id, sheikh_name, display_name) flag errors', () {
      final entry = createValidEntryJson(
        id: '',
        sheikhName: '   ',
        displayName: '',
      );
      final json = createValidCatalogJson(entries: [entry]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field.contains('id')), isTrue);
      expect(errors.any((e) => e.field.contains('sheikh_name')), isTrue);
      expect(errors.any((e) => e.field.contains('display_name')), isTrue);
    });

    test('ID without "remote:" prefix flags error', () {
      final entry = createValidEntryJson(id: 'sheikh_fajr');
      final json = createValidCatalogJson(entries: [entry]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field == 'entries[0].id'), isTrue);
      expect(errors.firstWhere((e) => e.field == 'entries[0].id').message, contains('remote:'));
    });

    test('Invalid audio_type flags error', () {
      final entry = createValidEntryJson(audioType: 'maghrib'); // unsupported audio type
      final json = createValidCatalogJson(entries: [entry]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field == 'entries[0].audio_type'), isTrue);
    });

    test('duration_seconds <= 0 flags error', () {
      final entry = createValidEntryJson(durationSeconds: 0);
      final json = createValidCatalogJson(entries: [entry]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field == 'entries[0].duration_seconds'), isTrue);
    });

    test('Path traversal in object_key flags error', () {
      final traversalSequences = [
        '../audio/mishary.mp3',
        'audio/../../secret.mp3',
        r'audio\mishary.mp3',
        '/audio/mishary.mp3',
        '//audio/mishary.mp3',
        'https://attacker.com/audio.mp3',
      ];

      for (final badKey in traversalSequences) {
        final entry = createValidEntryJson(objectKey: badKey);
        final json = createValidCatalogJson(entries: [entry]);
        final errors = validator.validateJson(json);

        expect(
          errors.any((e) => e.field == 'entries[0].object_key'),
          isTrue,
          reason: 'Failed for key: $badKey',
        );
      }
    });

    test('Unsupported audio file extension flags error', () {
      final badExtensions = ['audio.txt', 'audio.mp4', 'audio.exe', 'audio'];
      for (final badKey in badExtensions) {
        final entry = createValidEntryJson(objectKey: badKey);
        final json = createValidCatalogJson(entries: [entry]);
        final errors = validator.validateJson(json);

        expect(
          errors.any((e) => e.field == 'entries[0].object_key'),
          isTrue,
          reason: 'Failed for extension in: $badKey',
        );
      }
    });

    test('File size boundaries (<= 0 or > 30MB) flag errors', () {
      // Zero size
      final entryZero = createValidEntryJson(fileSizeBytes: 0);
      final errorsZero = validator.validateJson(createValidCatalogJson(entries: [entryZero]));
      expect(errorsZero.any((e) => e.field == 'entries[0].file_size_bytes'), isTrue);

      // Exceeds 30MB
      final entryTooBig = createValidEntryJson(fileSizeBytes: 30 * 1024 * 1024 + 1);
      final errorsTooBig = validator.validateJson(createValidCatalogJson(entries: [entryTooBig]));
      expect(errorsTooBig.any((e) => e.field == 'entries[0].file_size_bytes'), isTrue);

      // Exactly 30MB is allowed
      final entryExact30Mb = createValidEntryJson(fileSizeBytes: 30 * 1024 * 1024);
      final errorsExact = validator.validateJson(createValidCatalogJson(entries: [entryExact30Mb]));
      expect(errorsExact.any((e) => e.field == 'entries[0].file_size_bytes'), isFalse);
    });

    test('Invalid SHA-256 (length != 64, uppercase, non-hex) flags errors', () {
      final badSha256s = [
        'short_hash',
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', // uppercase
        'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz', // non-hex 'z'
        '${validSha256}a', // 65 chars
      ];

      for (final badSha in badSha256s) {
        final entry = createValidEntryJson(sha256: badSha);
        final json = createValidCatalogJson(entries: [entry]);
        final errors = validator.validateJson(json);

        expect(
          errors.any((e) => e.field == 'entries[0].sha256'),
          isTrue,
          reason: 'Failed for sha256: $badSha',
        );
      }
    });

    test('preview_offset_seconds boundaries (negative or >= duration) flag errors', () {
      final entryNegative = createValidEntryJson(previewOffsetSeconds: -1);
      final errorsNegative = validator.validateJson(createValidCatalogJson(entries: [entryNegative]));
      expect(errorsNegative.any((e) => e.field == 'entries[0].preview_offset_seconds'), isTrue);

      final entryExceeds = createValidEntryJson(durationSeconds: 100, previewOffsetSeconds: 100);
      final errorsExceeds = validator.validateJson(createValidCatalogJson(entries: [entryExceeds]));
      expect(errorsExceeds.any((e) => e.field == 'entries[0].preview_offset_seconds'), isTrue);
    });
  });

  group('AdhanCatalogValidator - Global Catalog Duplicate Detection', () {
    test('Duplicate entry IDs are detected and flagged with exact indices', () {
      final entry1 = createValidEntryJson(id: 'remote:sheikh_fajr', objectKey: 'audio/1.mp3');
      final entry2 = createValidEntryJson(id: 'remote:sheikh_fajr', objectKey: 'audio/2.mp3');

      final json = createValidCatalogJson(entries: [entry1, entry2]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field == 'entries[1].id'), isTrue);
      final duplicateError = errors.firstWhere((e) => e.field == 'entries[1].id');
      expect(duplicateError.message, contains('مكرر في الكتالوج'));
      expect(duplicateError.message, contains('العنصر #0'));
    });

    test('Duplicate object keys are detected and flagged with exact indices', () {
      final entry1 = createValidEntryJson(id: 'remote:fajr_1', objectKey: 'audio/same_audio.mp3');
      final entry2 = createValidEntryJson(id: 'remote:fajr_2', objectKey: 'audio/same_audio.mp3');

      final json = createValidCatalogJson(entries: [entry1, entry2]);
      final errors = validator.validateJson(json);

      expect(errors.any((e) => e.field == 'entries[1].object_key'), isTrue);
      final duplicateKeyError = errors.firstWhere((e) => e.field == 'entries[1].object_key');
      expect(duplicateKeyError.message, contains('مكرر في الكتالوج'));
      expect(duplicateKeyError.message, contains('العنصر #0'));
    });

    test('Distinct IDs and object keys pass validation with zero errors', () {
      final entry1 = createValidEntryJson(id: 'remote:fajr_1', objectKey: 'audio/audio_1.mp3');
      final entry2 = createValidEntryJson(id: 'remote:fajr_2', objectKey: 'audio/audio_2.mp3');

      final json = createValidCatalogJson(entries: [entry1, entry2]);
      final errors = validator.validateJson(json);
      expect(errors, isEmpty);
    });
  });

  group('Release Isolation Logic', () {
    test('CatalogDeveloperConfig computeIsActive returns false when not in debug mode', () {
      expect(
        CatalogDeveloperConfig.computeIsActive(isDebug: false, isFlagEnabled: true),
        isFalse,
      );
      expect(
        CatalogDeveloperConfig.computeIsActive(isDebug: false, isFlagEnabled: false),
        isFalse,
      );
    });

    test('CatalogDeveloperConfig computeIsActive returns false when flag is disabled in debug', () {
      expect(
        CatalogDeveloperConfig.computeIsActive(isDebug: true, isFlagEnabled: false),
        isFalse,
      );
    });

    test('CatalogDeveloperConfig computeIsActive returns true ONLY when in debug and flag is true', () {
      expect(
        CatalogDeveloperConfig.computeIsActive(isDebug: true, isFlagEnabled: true),
        isTrue,
      );
    });
  });
}
