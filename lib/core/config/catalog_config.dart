/// Build-time configuration for the remote adhan audio catalog.
///
/// ## URL injection via --dart-define
///
/// Set the catalog base URL at build time:
///
/// ```
/// flutter run --dart-define=CATALOG_BASE_URL=https://your-public-domain.com
/// flutter build apk --dart-define=CATALOG_BASE_URL=https://your-public-domain.com
/// ```
///
/// The base URL must be:
/// - HTTPS only (no plain HTTP allowed in production).
/// - A public delivery URL — NOT an S3/R2 API endpoint.
/// - Reachable from Flutter native (Android/iOS) HTTP clients without
///   authentication headers.
///
/// ## Development override
///
/// For local testing against a mock HTTP server, pass a localhost URL:
/// ```
/// flutter run --dart-define=CATALOG_BASE_URL=http://10.0.2.2:8080
/// ```
///
/// ## Undefined URL sentinel
///
/// When [CATALOG_BASE_URL] is not injected, [baseUrl] equals
/// [kCatalogBaseUrlUndefined]. The repository layer treats this as a
/// configuration error and surfaces [AdhanCatalogSourceError.unconfigured]
/// without attempting a network request.
library;

import 'package:flutter/foundation.dart';

/// Sentinel value returned by [CatalogConfig.baseUrl] when the build-time
/// constant has not been injected.
const String kCatalogBaseUrlUndefined = 'CATALOG_BASE_URL_NOT_SET';

/// Object key for the catalog JSON file within the R2 bucket.
const String kCatalogJsonObjectKey = 'adhan_catalog.json';

/// Maximum age of a locally cached catalog before a remote refresh is attempted.
const Duration kCatalogCacheTtl = Duration(hours: 24);

/// Maximum allowed size for the catalog JSON response (1 MB).
/// Responses larger than this are rejected to prevent memory abuse.
const int kCatalogJsonMaxBytes = 1 * 1024 * 1024;

/// Maximum allowed size for a single remote audio file download (30 MB).
/// Files larger than this are rejected before download begins.
const int kRemoteAudioMaxBytes = 30 * 1024 * 1024;

/// Maximum allowed storage quota for cached remote adhan audio files (150 MiB).
const int kRemoteAudioCacheQuotaBytes = 150 * 1024 * 1024;

/// HTTP request timeout for catalog JSON fetch.
const Duration kCatalogFetchTimeout = Duration(seconds: 15);

/// HTTP request timeout for audio file download.
const Duration kAudioDownloadTimeout = Duration(minutes: 3);

/// Build-time define passed via:
/// `--dart-define=ENABLE_CATALOG_DEV_TOOLS=true`
const bool kCatalogDeveloperToolsEnabled =
    bool.fromEnvironment('ENABLE_CATALOG_DEV_TOOLS', defaultValue: false);

/// Whether catalog developer tools are active.
///
/// In Release builds [kDebugMode] is a compile-time constant `false`,
/// ensuring [isCatalogDeveloperToolsActive] evaluates statically to `false`,
/// allowing the Dart compiler to tree-shake all developer code.
bool get isCatalogDeveloperToolsActive =>
    kDebugMode && kCatalogDeveloperToolsEnabled;

/// Compile-time configuration for the remote catalog feature.
abstract final class CatalogConfig {
  CatalogConfig._();

  /// Public HTTPS base URL for all catalog resources.
  ///
  /// Injected at build time via:
  /// ```
  /// --dart-define=CATALOG_BASE_URL=https://...
  /// ```
  ///
  /// Returns [kCatalogBaseUrlUndefined] when not set.
  static const String baseUrl = String.fromEnvironment(
    'CATALOG_BASE_URL',
    defaultValue: kCatalogBaseUrlUndefined,
  );

  /// Whether the base URL has been properly configured.
  static bool get isConfigured => baseUrl != kCatalogBaseUrlUndefined;

  /// Full URL to the catalog JSON file.
  /// Example: `https://cdn.example.com/adhan_catalog.json`
  static String get catalogJsonUrl {
    if (!isConfigured) return '$baseUrl/$kCatalogJsonObjectKey';
    final trimmed = baseUrl.trim();
    if (trimmed.toLowerCase().endsWith('.json')) {
      return trimmed;
    }
    return validateAndResolveUrl(kCatalogJsonObjectKey) ?? '$baseUrl/$kCatalogJsonObjectKey';
  }

  /// Resolves and strictly validates the full HTTPS URL for a remote audio file.
  ///
  /// ## SSRF and Path Traversal Protection
  /// Returns null if:
  /// - [baseUrl] is unconfigured and no [customBaseUrl] is supplied.
  /// - [objectKey] is empty, contains `..`, `\`, `://`, or starts with `//`.
  /// - The resolved URL host or port differs from the base URL (host spoofing / SSRF guard).
  /// - The URL scheme is not HTTPS (HTTP is strictly rejected, except on localhost for local testing).
  static String? audioUrl(String objectKey, {String? customBaseUrl}) {
    return validateAndResolveUrl(objectKey, customBaseUrl: customBaseUrl);
  }

  /// Secure URL resolver and validator.
  static String? validateAndResolveUrl(String objectKey, {String? customBaseUrl}) {
    var base = (customBaseUrl ?? (isConfigured ? baseUrl : null))?.trim();
    if (base == null || base.isEmpty) return null;

    final key = objectKey.trim();
    if (key.isEmpty) return null;

    // If the base URL was passed pointing directly to a .json file, strip the filename
    // to obtain the base directory for resolving audio object keys.
    if (base.toLowerCase().endsWith('.json')) {
      final lastSlash = base.lastIndexOf('/');
      if (lastSlash != -1) {
        base = base.substring(0, lastSlash);
      }
    }

    // Strict path traversal and scheme injection guards
    if (key.contains('..') ||
        key.contains(r'\') ||
        key.contains('://') ||
        key.startsWith('//')) {
      return null;
    }

    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) return null;

    // Reject non-HTTPS in production (allow HTTP only for localhost in testing/dev)
    final isLocalhost = baseUri.host == 'localhost' ||
        baseUri.host == '127.0.0.1' ||
        baseUri.host == '10.0.2.2';
    if (baseUri.scheme != 'https' && !isLocalhost) {
      return null;
    }

    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    var cleanKey = key.startsWith('/') ? key.substring(1) : key;

    // Deduplicate trailing folder segment if cleanKey repeats the base directory
    // (e.g. cleanBase is "https://example.com/catalog" and cleanKey is "catalog/audio/file.mp3")
    final baseSegments = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (baseSegments.isNotEmpty) {
      final lastSegment = baseSegments.last;
      if (cleanKey.startsWith('$lastSegment/')) {
        cleanKey = cleanKey.substring(lastSegment.length + 1);
      }
    }

    final resolvedUri = Uri.tryParse('$cleanBase/$cleanKey');
    if (resolvedUri == null) return null;

    // Validate that resolution didn't change scheme, host, or port (SSRF guard)
    if (resolvedUri.scheme != baseUri.scheme ||
        resolvedUri.host != baseUri.host ||
        resolvedUri.port != baseUri.port) {
      return null;
    }

    if (resolvedUri.path.contains('..')) return null;

    return resolvedUri.toString();
  }
}

