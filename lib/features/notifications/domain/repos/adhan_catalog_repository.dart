import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';

/// Contract for retrieving and caching the remote adhan audio catalog.
abstract class BaseAdhanCatalogRepository {
  /// Fetches the catalog, using the cached catalog if it is still within TTL
  /// unless [forceRefresh] is true.
  ///
  /// ## Safe Fallback & Corrupt Response Protection
  /// If remote retrieval fails, times out, or returns a completely corrupted catalog:
  /// - The repository falls back to the last known valid cached catalog.
  /// - A failure is returned only if no valid cached copy exists.
  /// - An invalid remote response NEVER replaces a valid cached catalog.
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false});

  /// Reads the last known valid catalog stored locally without initiating network requests.
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog();

  /// Clears the local catalog cache and metadata.
  Future<void> clearCache();
}

