import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/entities/catalog_validation_error.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:path/path.dart' as p;

/// Strictly validates remote adhan audio catalog JSON structures and in-memory models.
///
/// Ensures 100% contract parity with Phase 1 data models ([AdhanCatalog] and [AdhanCatalogEntry])
/// while performing deep static analysis:
/// - Exact Schema v1 compliance.
/// - RFC 3339 / ISO 8601 UTC timestamp verification.
/// - Field-level constraints (non-empty strings, positive sizes and durations).
/// - Path traversal and extension safety.
/// - Cryptographic 64-character lowercase SHA-256 hex format.
/// - Duplicate ID and duplicate objectKey detection across all entries.
class AdhanCatalogValidator {
  const AdhanCatalogValidator();

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  /// Validates a raw JSON map representation of a catalog.
  ///
  /// Returns a list of [CatalogValidationError]. An empty list indicates
  /// full contract validity.
  List<CatalogValidationError> validateJson(Map<String, dynamic> json) {
    final errors = <CatalogValidationError>[];

    // 1. Schema version validation
    final rawVersion = json['schema_version'];
    if (rawVersion == null) {
      errors.add(
        const CatalogValidationError(
          field: 'schema_version',
          message: 'حقل "schema_version" مطلوب ولا يمكن أن يكون فارغاً.',
        ),
      );
    } else if (rawVersion is! int) {
      errors.add(
        CatalogValidationError(
          field: 'schema_version',
          message: 'حقل "schema_version" يجب أن يكون رقماً صحيحاً (القيمة الحالية: ${rawVersion.runtimeType}).',
        ),
      );
    } else if (rawVersion != kCatalogSchemaVersion) {
      errors.add(
        CatalogValidationError(
          field: 'schema_version',
          message: 'إصدار المخطط غير مدعوم: $rawVersion (الإصدار المدعوم هو: $kCatalogSchemaVersion).',
        ),
      );
    }

    // 2. Timestamp validation (generated_at)
    final rawGeneratedAt = json['generated_at'];
    if (rawGeneratedAt != null) {
      if (rawGeneratedAt is! String) {
        errors.add(
          const CatalogValidationError(
            field: 'generated_at',
            message: 'حقل "generated_at" يجب أن يكون نصاً بتنسيق ISO 8601 UTC.',
          ),
        );
      } else {
        final parsedDate = DateTime.tryParse(rawGeneratedAt);
        final isUtc = rawGeneratedAt.endsWith('Z') || rawGeneratedAt.endsWith('+00:00');
        if (parsedDate == null || !isUtc) {
          errors.add(
            CatalogValidationError(
              field: 'generated_at',
              message: 'حقل "generated_at" ليس بتنسيق UTC ISO 8601 صالح (مثال: "2026-11-13T12:00:00Z").',
            ),
          );
        }
      }
    }

    // 3. Entries array validation
    final rawEntries = json['entries'];
    if (rawEntries == null) {
      errors.add(
        const CatalogValidationError(
          field: 'entries',
          message: 'مصفوفة "entries" مطلوبة ولا يمكن أن تكون فارغة.',
        ),
      );
      return errors;
    }

    if (rawEntries is! List) {
      errors.add(
        CatalogValidationError(
          field: 'entries',
          message: 'حقل "entries" يجب أن يكون مصفوفة JSON (قائمة).',
        ),
      );
      return errors;
    }

    // 4. Validate entries & detect duplicates
    final seenIds = <String, int>{}; // id -> first seen index
    final seenKeys = <String, int>{}; // objectKey -> first seen index

    for (int i = 0; i < rawEntries.length; i++) {
      final item = rawEntries[i];
      if (item is! Map<String, dynamic>) {
        errors.add(
          CatalogValidationError(
            field: 'entries[$i]',
            message: 'العنصر رقم #$i في الكتالوج ليس كائناً صالحاً (JSON Object).',
            entryIndex: i,
          ),
        );
        continue;
      }

      final entryErrors = _validateEntryMap(item, i);
      errors.addAll(entryErrors);

      // Check duplicates only if id / objectKey are non-empty strings
      final id = item['id'];
      if (id is String && id.trim().isNotEmpty) {
        if (seenIds.containsKey(id)) {
          errors.add(
            CatalogValidationError(
              field: 'entries[$i].id',
              message: 'معرف الأذان مكرر في الكتالوج: "$id" (موجود مسبقاً في العنصر #${seenIds[id]}).',
              entryIndex: i,
              entryId: id,
            ),
          );
        } else {
          seenIds[id] = i;
        }
      }

      final objectKey = item['object_key'];
      if (objectKey is String && objectKey.trim().isNotEmpty) {
        if (seenKeys.containsKey(objectKey)) {
          errors.add(
            CatalogValidationError(
              field: 'entries[$i].object_key',
              message: 'مسار الملف الصوتي (object_key) مكرر في الكتالوج: "$objectKey" (مستخدم في العنصر #${seenKeys[objectKey]}).',
              entryIndex: i,
              entryId: id is String ? id : null,
            ),
          );
        } else {
          seenKeys[objectKey] = i;
        }
      }
    }

    // 5. Cross-check with Phase 1 parser: guarantee single source of truth
    if (errors.isEmpty) {
      try {
        final parsed = AdhanCatalog.fromJson(json);
        if (parsed.droppedEntriesCount > 0) {
          errors.add(
            CatalogValidationError(
              field: 'entries',
              message: 'الكتالوج يحتوي على ${parsed.droppedEntriesCount} عنصر غير صالح تم إسقاطه بواسطة النموذج الرئيسي.',
            ),
          );
        }
      } catch (e) {
        errors.add(
          CatalogValidationError(
            field: 'catalog',
            message: 'فشل تحليل الكتالوج بواسطة نموذج Phase 1: $e',
          ),
        );
      }
    }

    return errors;
  }

  /// Validates an in-memory [AdhanCatalog] model instance.
  List<CatalogValidationError> validateCatalog(AdhanCatalog catalog) {
    return validateJson(catalog.toJson());
  }

  /// Internal helper to validate a single entry map.
  List<CatalogValidationError> _validateEntryMap(Map<String, dynamic> json, int index) {
    final errors = <CatalogValidationError>[];
    final id = json['id'] as String? ?? '';
    final entryId = id.isNotEmpty ? id : null;

    // ID validation
    if (id.isEmpty) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].id',
          message: 'معرف الأذان (id) مطلوب ولا يمكن أن يكون فارغاً.',
          entryIndex: index,
        ),
      );
    } else if (!id.startsWith('remote:')) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].id',
          message: 'معرف الأذان يجب أن يبدأ بـ "remote:" (القيمة: "$id").',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    } else if (id.trim().length <= 'remote:'.length) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].id',
          message: 'معرف الأذان يجب أن يحتوي على اسم فريد بعد البادئة "remote:".',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Sheikh Name
    final sheikhName = json['sheikh_name'] as String? ?? '';
    if (sheikhName.trim().isEmpty) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].sheikh_name',
          message: 'اسم الشيخ مطلوب ولا يمكن أن يكون فارغاً.',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Display Name
    final displayName = json['display_name'] as String? ?? '';
    if (displayName.trim().isEmpty) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].display_name',
          message: 'اسم الأذان المعروض مطلوب ولا يمكن أن يكون فارغاً.',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Audio Type
    final audioTypeRaw = json['audio_type'] as String? ?? '';
    final audioType = AdhanAudioType.fromKey(audioTypeRaw);
    if (audioType == null) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].audio_type',
          message: 'نوع الأذان غير معروف أو غير مدعوم: "$audioTypeRaw" (الأنواع المدعومة: ${CatalogDeveloperConfig.allowedAudioTypeKeys.join(', ')}).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Duration Seconds
    final duration = (json['duration_seconds'] as num?)?.toInt() ?? 0;
    if (duration <= 0) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].duration_seconds',
          message: 'مدة الأذان بالثواني يجب أن تكون رقماً موجباً أكبر من 0 (القيمة: $duration).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Object Key & Path Traversal Guards
    final objectKey = json['object_key'] as String? ?? '';
    if (objectKey.trim().isEmpty) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].object_key',
          message: 'مسار الملف الصوتي (object_key) مطلوب.',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    } else {
      if (objectKey.contains('..') ||
          objectKey.contains(r'\') ||
          objectKey.contains('://') ||
          objectKey.startsWith('//') ||
          objectKey.startsWith('/')) {
        errors.add(
          CatalogValidationError(
            field: 'entries[$index].object_key',
            message: 'مسار الملف غير آمن أو يحتوي على محاولة اجتياز مسار (Path Traversal): "$objectKey".',
            entryIndex: index,
            entryId: entryId,
          ),
        );
      }

      final ext = p.extension(objectKey).toLowerCase();
      if (!CatalogDeveloperConfig.allowedAudioExtensions.contains(ext)) {
        errors.add(
          CatalogValidationError(
            field: 'entries[$index].object_key',
            message: 'صيغة الملف غير مدعومة: "$ext" (الصيغ المدعومة: ${CatalogDeveloperConfig.allowedAudioExtensions.join(', ')}).',
            entryIndex: index,
            entryId: entryId,
          ),
        );
      }
    }

    // File Size Bytes
    final fileSizeBytes = (json['file_size_bytes'] as num?)?.toInt() ?? 0;
    if (fileSizeBytes <= 0) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].file_size_bytes',
          message: 'حجم الملف بالبايت يجب أن يكون أكبر من 0 (القيمة: $fileSizeBytes).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    } else if (fileSizeBytes > kRemoteAudioMaxBytes) {
      final maxMiB = kRemoteAudioMaxBytes ~/ (1024 * 1024);
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].file_size_bytes',
          message: 'حجم الملف ($fileSizeBytes بايت) يتجاوز الحد الأقصى المسموح به ($maxMiB MiB = $kRemoteAudioMaxBytes بايت).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // SHA-256 Checksum
    final sha256 = json['sha256'] as String? ?? '';
    if (sha256.isEmpty) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].sha256',
          message: 'بصمة التحقق SHA-256 مطلوبة.',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    } else if (!_sha256Pattern.hasMatch(sha256)) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].sha256',
          message: 'بصمة SHA-256 غير صحيحة: يجب أن تتكون من 64 حرفاً بالنظام الست عشري الصغير (lowercase hex).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    // Preview Offset Seconds
    final previewOffset = (json['preview_offset_seconds'] as num?)?.toInt() ?? 0;
    if (previewOffset < 0) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].preview_offset_seconds',
          message: 'بداية المعاينة (preview_offset_seconds) لا يمكن أن تكون سالبة.',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    } else if (duration > 0 && previewOffset >= duration) {
      errors.add(
        CatalogValidationError(
          field: 'entries[$index].preview_offset_seconds',
          message: 'بداية المعاينة ($previewOffset ثانية) يجب أن تكون أقل من مدة الملف الإجمالية ($duration ثانية).',
          entryIndex: index,
          entryId: entryId,
        ),
      );
    }

    return errors;
  }
}
