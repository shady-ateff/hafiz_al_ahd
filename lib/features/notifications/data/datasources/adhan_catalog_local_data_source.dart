import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/errors/adhan_catalog_exceptions.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';

abstract class BaseAdhanCatalogLocalDataSource {
  Future<AdhanCatalog?> getCachedCatalog();
  Future<void> saveCatalog(
    AdhanCatalog catalog, {
    String? etag,
    DateTime? timestamp,
  });
  Future<DateTime?> getLastCachedTime();
  Future<String?> getCachedEtag();
  Future<bool> isCacheExpired({Duration ttl = kCatalogCacheTtl});
  Future<void> updateTimestamp({DateTime? timestamp});
  Future<void> clearCache();
}

class AdhanCatalogLocalDataSourceImpl implements BaseAdhanCatalogLocalDataSource {
  static const String keyCatalogEnvelope = 'cached_adhan_catalog_envelope';
  static const String keyCatalogJson = 'cached_adhan_catalog_json';
  static const String keyCatalogTimestamp = 'cached_adhan_catalog_timestamp';
  static const String keyCatalogEtag = 'cached_adhan_catalog_etag';

  final SharedPreferences prefs;

  AdhanCatalogLocalDataSourceImpl({required this.prefs});

  @override
  Future<AdhanCatalog?> getCachedCatalog() async {
    try {
      // 1. Try reading the atomic envelope
      final envelopeStr = prefs.getString(keyCatalogEnvelope);
      if (envelopeStr != null && envelopeStr.trim().isNotEmpty) {
        final decoded = jsonDecode(envelopeStr);
        if (decoded is Map<String, dynamic> && decoded['catalog'] is Map<String, dynamic>) {
          return AdhanCatalog.fromJson(decoded['catalog'] as Map<String, dynamic>);
        }
      }

      // 2. Legacy fallback
      final jsonString = prefs.getString(keyCatalogJson);
      if (jsonString != null && jsonString.trim().isNotEmpty) {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, dynamic>) {
          return AdhanCatalog.fromJson(decoded);
        }
      }

      return null;
    } catch (e) {
      // If cached data is malformed, treat as cache miss rather than crashing
      return null;
    }
  }

  @override
  Future<void> saveCatalog(
    AdhanCatalog catalog, {
    String? etag,
    DateTime? timestamp,
  }) async {
    try {
      final nowMillis = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;

      // Atomic single-key envelope storage
      final envelope = <String, dynamic>{
        'schema_version': catalog.schemaVersion,
        'timestamp': nowMillis,
        'etag': etag,
        'catalog': catalog.toJson(),
      };

      final envelopeStr = jsonEncode(envelope);
      await prefs.setString(keyCatalogEnvelope, envelopeStr);

      // Keep legacy keys updated for backward compatibility
      await prefs.setString(keyCatalogJson, jsonEncode(catalog.toJson()));
      await prefs.setInt(keyCatalogTimestamp, nowMillis);
      if (etag != null && etag.isNotEmpty) {
        await prefs.setString(keyCatalogEtag, etag);
      }
    } catch (e) {
      throw CatalogStorageException('Failed to persist catalog cache: $e');
    }
  }

  @override
  Future<DateTime?> getLastCachedTime() async {
    final envelopeStr = prefs.getString(keyCatalogEnvelope);
    if (envelopeStr != null && envelopeStr.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(envelopeStr);
        if (decoded is Map<String, dynamic> && decoded['timestamp'] is int) {
          return DateTime.fromMillisecondsSinceEpoch(decoded['timestamp'] as int);
        }
      } catch (_) {}
    }

    final millis = prefs.getInt(keyCatalogTimestamp);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<String?> getCachedEtag() async {
    final envelopeStr = prefs.getString(keyCatalogEnvelope);
    if (envelopeStr != null && envelopeStr.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(envelopeStr);
        if (decoded is Map<String, dynamic>) {
          return decoded['etag'] as String?;
        }
      } catch (_) {}
    }

    return prefs.getString(keyCatalogEtag);
  }

  @override
  Future<bool> isCacheExpired({Duration ttl = kCatalogCacheTtl}) async {
    final lastTime = await getLastCachedTime();
    if (lastTime == null) return true;

    final hasData = prefs.getString(keyCatalogEnvelope) != null ||
        prefs.getString(keyCatalogJson) != null;
    if (!hasData) return true;

    final age = DateTime.now().difference(lastTime);
    return age > ttl;
  }

  @override
  Future<void> updateTimestamp({DateTime? timestamp}) async {
    final nowMillis = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    final envelopeStr = prefs.getString(keyCatalogEnvelope);
    if (envelopeStr != null && envelopeStr.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(envelopeStr);
        if (decoded is Map<String, dynamic>) {
          decoded['timestamp'] = nowMillis;
          await prefs.setString(keyCatalogEnvelope, jsonEncode(decoded));
        }
      } catch (_) {}
    }

    await prefs.setInt(keyCatalogTimestamp, nowMillis);
  }

  @override
  Future<void> clearCache() async {
    await prefs.remove(keyCatalogEnvelope);
    await prefs.remove(keyCatalogJson);
    await prefs.remove(keyCatalogTimestamp);
    await prefs.remove(keyCatalogEtag);
  }
}

