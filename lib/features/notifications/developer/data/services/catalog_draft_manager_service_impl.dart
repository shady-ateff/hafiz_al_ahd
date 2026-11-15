import 'dart:convert';
import 'dart:io';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Concrete implementation of [CatalogDraftManagerService] with atomic file operations
/// and multi-layer reset safeguards.
class CatalogDraftManagerServiceImpl implements CatalogDraftManagerService {
  final Future<Directory> Function() _storageDirProvider;
  final BaseAdhanCatalogRepository _catalogRepository;
  final AdhanCatalogValidator _validator;

  CatalogDraftManagerServiceImpl({
    Future<Directory> Function()? storageDirProvider,
    required BaseAdhanCatalogRepository catalogRepository,
    AdhanCatalogValidator? validator,
  })  : _storageDirProvider = storageDirProvider ?? getApplicationDocumentsDirectory,
        _catalogRepository = catalogRepository,
        _validator = validator ?? const AdhanCatalogValidator();

  Future<Directory> _getDirectory() async {
    final dir = await _storageDirProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _getDraftFile() async {
    final dir = await _getDirectory();
    return File(p.join(dir.path, CatalogDeveloperConfig.draftFileName));
  }

  Future<File> _getTempDraftFile() async {
    final dir = await _getDirectory();
    return File(p.join(dir.path, CatalogDeveloperConfig.draftTempFileName));
  }

  @override
  Future<AdhanCatalog?> loadDraft() async {
    final file = await _getDraftFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final length = await file.length();
      if (length > CatalogDeveloperConfig.maxDraftSizeBytes) {
        throw CatalogDraftCorruptException(
          'ملف المسودة يتجاوز الحد الأقصى للحجم (${length ~/ 1024} كيلوبايت > ${CatalogDeveloperConfig.maxDraftSizeBytes ~/ 1024} كيلوبايت).',
        );
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        throw const CatalogDraftCorruptException('ملف المسودة فارغ تماماً.');
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const CatalogDraftCorruptException('بنية ملف المسودة غير صالحة (ليست كائن JSON).');
      }

      return AdhanCatalog.fromJson(decoded);
    } on CatalogDraftCorruptException {
      rethrow;
    } on FormatException catch (e) {
      throw CatalogDraftCorruptException('تنسيق JSON تالف في ملف المسودة: ${e.message}');
    } on AdhanCatalogParseException catch (e) {
      throw CatalogDraftCorruptException('فشل تحليل الكتالوج: ${e.message}');
    } catch (e) {
      throw CatalogDraftStorageException('خطأ غير متوقع أثناء قراءة المسودة: $e');
    }
  }

  @override
  Future<void> saveDraft(AdhanCatalog draft) async {
    File? tempFile;
    try {
      final draftFile = await _getDraftFile();
      tempFile = await _getTempDraftFile();

      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(draft.toJson());

      // 1. Write to temporary file with flush
      await tempFile.writeAsString(jsonString, flush: true);

      // 2. Atomic rename to target file
      // On POSIX and modern Windows, renaming an existing file atomically replaces target
      if (Platform.isWindows && await draftFile.exists()) {
        // On Windows FileSystem, replacing an open/existing file via rename can require delete first
        // If rename fails, we handle safely
        await draftFile.delete();
      }
      await tempFile.rename(draftFile.path);
    } catch (e) {
      // Cleanup temp file if dangling
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw CatalogDraftStorageException('فشل حفظ المسودة على القرص: $e');
    }
  }

  @override
  Future<AdhanCatalog> resetDraftToLive({required bool confirmReset}) async {
    if (!confirmReset) {
      throw const CatalogDraftResetRejectedException(
        'يجب تأكيد إعادة تعيين المسودة صراحة لمنع فقدان التعديلات غير المحفوظة.',
      );
    }

    // Step 1: Try fetching live catalog from repository
    AdhanCatalog? seedCatalog;
    try {
      final liveResult = await _catalogRepository.getCatalog(forceRefresh: true);
      liveResult.fold(
        (failure) {
          // Network or server failure, seedCatalog remains null to trigger fallback
        },
        (catalog) {
          if (!catalog.isCompletelyCorrupt) {
            final validationErrors = _validator.validateCatalog(catalog);
            if (validationErrors.isEmpty) {
              seedCatalog = catalog;
            }
          }
        },
      );
    } catch (_) {
      // Live fetch error, proceed to fallback
    }

    // Step 2: Fall back to last valid cached catalog if live fetch was unavailable/invalid
    if (seedCatalog == null) {
      try {
        final cachedResult = await _catalogRepository.getCachedCatalog();
        cachedResult.fold(
          (failure) {},
          (cachedCatalog) {
            if (!cachedCatalog.isCompletelyCorrupt) {
              final validationErrors = _validator.validateCatalog(cachedCatalog);
              if (validationErrors.isEmpty) {
                seedCatalog = cachedCatalog;
              }
            }
          },
        );
      } catch (_) {
        // Cache read error
      }
    }

    // Step 3: If neither live nor cache is valid/available, REJECT reset without touching draft
    if (seedCatalog == null) {
      throw const CatalogDraftResetUnavailableException(
        'تعذر الحصول على نسخة صالحة من الكتالوج (المباشر أو المخزن مؤقتاً). تم الإبقاء على المسودة الحالية دون تغيير.',
      );
    }

    // Step 4: Atomically persist the verified seed catalog as the new draft
    await saveDraft(seedCatalog!);
    return seedCatalog!;
  }

  @override
  String exportDraftJson(AdhanCatalog draft) {
    final errors = _validator.validateCatalog(draft);
    if (errors.isNotEmpty) {
      throw CatalogDraftExportValidationException(errors);
    }

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(draft.toJson());
  }

  @override
  Future<void> deleteDraft() async {
    try {
      final draftFile = await _getDraftFile();
      if (await draftFile.exists()) {
        await draftFile.delete();
      }
      final tempFile = await _getTempDraftFile();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      throw CatalogDraftStorageException('فشل حذف المسودة: $e');
    }
  }
}
