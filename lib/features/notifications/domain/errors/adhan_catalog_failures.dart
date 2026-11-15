import 'package:hafiz_al_ahd/core/errors/failure.dart';

/// Base failure type for all remote adhan catalog operations.
abstract class AdhanCatalogFailure extends Failure {
  AdhanCatalogFailure({required super.message});
}

/// Base URL is unconfigured (e.g. CATALOG_BASE_URL was not passed via --dart-define).
class CatalogUnconfiguredFailure extends AdhanCatalogFailure {
  CatalogUnconfiguredFailure({
    super.message = 'عنوان خادم كتالوج الأذان غير مهيأ (CATALOG_BASE_URL_NOT_SET).',
  });
}

/// Network connectivity issue or request timeout.
class CatalogNetworkFailure extends AdhanCatalogFailure {
  CatalogNetworkFailure({
    super.message = 'تعذر الاتصال بالخادم لجلب كتالوج الأذان. يرجى التحقق من اتصال الإنترنت.',
  });
}

/// Server returned an HTTP error (4xx / 5xx) other than 404.
class CatalogServerFailure extends AdhanCatalogFailure {
  final int? statusCode;
  CatalogServerFailure({
    this.statusCode,
    String? message,
  }) : super(
          message: message ??
              'فشل جلب كتالوج الأذان من الخادم (رمز الاستجابة: ${statusCode ?? 'غير معروف'}).',
        );
}

/// The remote catalog resource was not found (HTTP 404).
class CatalogNotFoundFailure extends AdhanCatalogFailure {
  CatalogNotFoundFailure({
    super.message = 'ملف كتالوج الأذان غير موجود على الخادم (404).',
  });
}

/// Catalog payload could not be parsed as valid JSON or violates schema constraints.
class CatalogParseFailure extends AdhanCatalogFailure {
  CatalogParseFailure({
    super.message = 'صيغة كتالوج الأذان المستلمة من الخادم غير صالحة أو غير متوافقة.',
  });
}

/// Catalog entries array had elements, but all of them were corrupted/dropped.
/// A completely corrupt catalog must not overwrite existing cache.
class CatalogCorruptFailure extends AdhanCatalogFailure {
  CatalogCorruptFailure({
    super.message = 'جميع ملفات الصوت داخل كتالوج الأذان المستلم غير صالحة.',
  });
}

/// Reading from or writing to the local catalog cache failed.
class CatalogCacheFailure extends AdhanCatalogFailure {
  CatalogCacheFailure({
    super.message = 'فشل الوصول إلى النسخة المخزنة محلياً من كتالوج الأذان.',
  });
}

/// No cached catalog is available when attempting an offline fallback.
class CatalogCacheNotFoundFailure extends AdhanCatalogFailure {
  CatalogCacheNotFoundFailure({
    super.message = 'لا توجد نسخة سابقة مخزنة من كتالوج الأذان للعمل بدون إنترنت.',
  });
}

