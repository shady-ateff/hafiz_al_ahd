import 'dart:developer';
import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/errors/adhan_catalog_exceptions.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';

class AdhanCatalogRepositoryImpl implements BaseAdhanCatalogRepository {
  final BaseAdhanCatalogRemoteDataSource remoteDataSource;
  final BaseAdhanCatalogLocalDataSource localDataSource;
  final String? customBaseUrl;

  AdhanCatalogRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    this.customBaseUrl,
  });

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    try {
      final cached = await localDataSource.getCachedCatalog();
      if (cached != null) {
        return Right(cached);
      }
      return Left(CatalogCacheNotFoundFailure());
    } catch (e) {
      return Left(CatalogCacheFailure(message: 'فشل قراءة الكتالوج المخزن محلياً: $e'));
    }
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({
    bool forceRefresh = false,
  }) async {
    // 1. Cache-first strategy: Return valid cache if unexpired and not forced
    if (!forceRefresh) {
      final isExpired = await localDataSource.isCacheExpired();
      if (!isExpired) {
        final cached = await localDataSource.getCachedCatalog();
        if (cached != null) {
          return Right(cached);
        }
      }
    }

    // 2. Pre-check Base URL configuration
    final isConfigured = customBaseUrl != null || CatalogConfig.isConfigured;
    if (!isConfigured) {
      // Offline / Unconfigured fallback: Use cached if available
      final cached = await localDataSource.getCachedCatalog();
      if (cached != null) {
        return Right(cached);
      }
      return Left(CatalogUnconfiguredFailure());
    }

    // 3. Attempt Remote Fetch
    try {
      final etag = await localDataSource.getCachedEtag();
      final targetUrl = customBaseUrl != null
          ? CatalogConfig.validateAndResolveUrl(
              kCatalogJsonObjectKey,
              customBaseUrl: customBaseUrl,
            )
          : CatalogConfig.catalogJsonUrl;

      final response = await remoteDataSource.fetchCatalog(
        ifNoneMatch: etag,
        customUrl: targetUrl,
      );

      // Handle 304 Not Modified
      if (response is RemoteCatalogNotModified) {
        await localDataSource.updateTimestamp();
        final cached = await localDataSource.getCachedCatalog();
        if (cached != null) {
          return Right(cached);
        }
        // If cache was unexpectedly lost, force full re-fetch without ETag
        return _fetchFreshAndCache(customUrl: targetUrl);
      }

      // Handle 200 OK
      if (response is RemoteCatalogSuccess) {
        return _processAndCacheCatalog(
          json: response.json,
          etag: response.etag,
        );
      }

      throw const CatalogNetworkException('Unknown remote catalog response');
    } on CatalogNotFoundException {
      return _fallbackToCacheOrFailure(CatalogNotFoundFailure());
    } on CatalogHttpException catch (e) {
      return _fallbackToCacheOrFailure(
        CatalogServerFailure(statusCode: e.statusCode, message: e.message),
      );
    } on CatalogNetworkException catch (e) {
      return _fallbackToCacheOrFailure(
        CatalogNetworkFailure(message: e.message),
      );
    } on AdhanCatalogParseException catch (e) {
      return _fallbackToCacheOrFailure(
        CatalogParseFailure(message: e.message),
      );
    } catch (e) {
      return _fallbackToCacheOrFailure(
        CatalogServerFailure(message: 'خطأ غير متوقع أثناء معالجة الكتالوج: $e'),
      );
    }
  }

  /// Forces a fresh catalog fetch without ETag header.
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> _fetchFreshAndCache({
    String? customUrl,
  }) async {
    try {
      final response = await remoteDataSource.fetchCatalog(customUrl: customUrl);
      if (response is RemoteCatalogSuccess) {
        return _processAndCacheCatalog(
          json: response.json,
          etag: response.etag,
        );
      }
      return _fallbackToCacheOrFailure(
        CatalogServerFailure(message: 'فشل استرجاع الكتالوج بعد تجديد الطلب'),
      );
    } catch (e) {
      return _fallbackToCacheOrFailure(
        CatalogNetworkFailure(message: e.toString()),
      );
    }
  }

  /// Validates and parses the remote JSON payload, protecting against corrupt replacement.
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> _processAndCacheCatalog({
    required Map<String, dynamic> json,
    String? etag,
  }) async {
    final catalog = AdhanCatalog.fromJson(json);

    // Reservation B Guard: If entries were sent, but ALL of them are corrupt:
    // Do NOT overwrite local cache with empty entries!
    if (catalog.isCompletelyCorrupt) {
      log('⚠️ [AdhanCatalogRepository] Received completely corrupted catalog payload. Rejecting cache overwrite.');
      return _fallbackToCacheOrFailure(CatalogCorruptFailure());
    }

    if (catalog.isPartiallyValid) {
      log('ℹ️ [AdhanCatalogRepository] Catalog partially valid: ${catalog.entries.length} valid, ${catalog.droppedEntriesCount} dropped.');
    }

    // Persist valid or sanitized catalog
    await localDataSource.saveCatalog(catalog, etag: etag);
    return Right(catalog);
  }

  /// Attempts to return the last known valid local cache; surfaces [failure] if no cache exists.
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> _fallbackToCacheOrFailure(
    AdhanCatalogFailure failure,
  ) async {
    try {
      final cached = await localDataSource.getCachedCatalog();
      if (cached != null) {
        log('ℹ️ [AdhanCatalogRepository] Remote failed (${failure.runtimeType}). Falling back to cached catalog.');
        return Right(cached);
      }
    } catch (_) {}

    return Left(failure);
  }

  @override
  Future<void> clearCache() async {
    await localDataSource.clearCache();
  }
}

