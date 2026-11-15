import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/adhan_catalog_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AdhanCatalogLocalDataSourceImpl localDataSource;
  HttpServer? mockServer;
  String? mockServerBaseUrl;

  final sampleValidCatalogMap = {
    'schema_version': 1,
    'generated_at': '2026-11-14T12:00:00Z',
    'entries': [
      {
        'id': 'remote:makkah_sheikh_ali',
        'sheikh_name': 'الشيخ علي جابر',
        'audio_type': 'general',
        'display_name': 'أذان مكة المكرمة الخاشع',
        'duration_seconds': 72,
        'object_key': 'audio/makkah_ali.mp3',
        'file_size_bytes': 2500000,
        'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      },
      {
        'id': 'remote:madinah_fajr',
        'sheikh_name': 'الشيخ عبد المجيد السريحي',
        'audio_type': 'fajr',
        'display_name': 'أذان فجر المدينة النبوية',
        'duration_seconds': 95,
        'object_key': 'audio/madinah_fajr.mp3',
        'file_size_bytes': 3200000,
        'sha256': 'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb',
      }
    ]
  };

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    localDataSource = AdhanCatalogLocalDataSourceImpl(prefs: prefs);
  });

  tearDown(() async {
    await mockServer?.close(force: true);
    mockServer = null;
    mockServerBaseUrl = null;
  });

  group('Phase 6.1 — Remote Catalog Physical & Integration Verification', () {
    test('E2E-01 [Cold Launch & Cache Storage]: Successfully fetches, parses Schema v1, and caches to disk envelope', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      const etagValue = '"v1.0.0-catalog-etag"';
      mockServer!.listen((HttpRequest request) {
        if (request.uri.path == '/$kCatalogJsonObjectKey') {
          request.response.headers.set('ETag', etagValue);
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode(sampleValidCatalogMap));
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });

      final remoteDataSource = AdhanCatalogRemoteDataSourceImpl(client: http.Client());
      final repository = AdhanCatalogRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
        customBaseUrl: mockServerBaseUrl,
      );

      // Cold launch fetch
      final result = await repository.getCatalog(forceRefresh: true);

      expect(result.isRight(), isTrue);
      final catalog = result.getOrElse(() => throw Exception('Failed to get catalog'));
      expect(catalog.schemaVersion, equals(1));
      expect(catalog.entries.length, equals(2));
      expect(catalog.entries.first.sheikhName, equals('الشيخ علي جابر'));

      // Verify persistent envelope in SharedPreferences
      final cachedEtag = await localDataSource.getCachedEtag();
      expect(cachedEtag, equals(etagValue));

      final cachedCatalog = await localDataSource.getCachedCatalog();
      expect(cachedCatalog, isNotNull);
      expect(cachedCatalog!.entries.length, equals(2));
    });

    test('E2E-02 [Cache Hit & Offline Operation]: Loads instantly from local disk cache when offline', () async {
      // Pre-populate disk cache with valid envelope
      final catalog = AdhanCatalog.fromJson(sampleValidCatalogMap);
      await localDataSource.saveCatalog(
        catalog,
        etag: '"offline-etag"',
        timestamp: DateTime.now(),
      );

      // Create repository with unreachable / dead server port (simulating offline mode)
      final remoteDataSource = AdhanCatalogRemoteDataSourceImpl(client: http.Client());
      final repository = AdhanCatalogRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
        customBaseUrl: 'http://127.0.0.1:54321', // Offline port
      );

      // Regular getCatalog() without forced refresh hits cache immediately
      final result = await repository.getCatalog(forceRefresh: false);

      expect(result.isRight(), isTrue);
      final resolvedCatalog = result.getOrElse(() => throw Exception());
      expect(resolvedCatalog.entries.length, equals(2));
      expect(resolvedCatalog.entries.last.displayName, contains('فجر المدينة'));
    });

    test('E2E-03 [ETag / HTTP 304 Handling]: Returns cached catalog and updates timestamp on 304 Not Modified', () async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      const etagValue = '"stable-etag-12345"';
      bool receivedIfNoneMatch = false;

      mockServer!.listen((HttpRequest request) {
        if (request.uri.path == '/$kCatalogJsonObjectKey') {
          final ifNoneMatch = request.headers.value('if-none-match');
          if (ifNoneMatch == etagValue) {
            receivedIfNoneMatch = true;
            request.response.statusCode = HttpStatus.notModified;
            request.response.close();
            return;
          }
        }
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });

      // Save initial cache with etag
      final initialCatalog = AdhanCatalog.fromJson(sampleValidCatalogMap);
      final staleTimestamp = DateTime.now().subtract(const Duration(hours: 48));
      await localDataSource.saveCatalog(
        initialCatalog,
        etag: etagValue,
        timestamp: staleTimestamp,
      );

      final remoteDataSource = AdhanCatalogRemoteDataSourceImpl(client: http.Client());
      final repository = AdhanCatalogRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
        customBaseUrl: mockServerBaseUrl,
      );

      // Force refresh with server
      final result = await repository.getCatalog(forceRefresh: true);

      expect(receivedIfNoneMatch, isTrue);
      expect(result.isRight(), isTrue);
      final catalog = result.getOrElse(() => throw Exception());
      expect(catalog.entries.length, equals(2));

      // Timestamp was updated to current time
      final updatedTime = await localDataSource.getLastCachedTime();
      expect(updatedTime, isNotNull);
      expect(updatedTime!.isAfter(staleTimestamp), isTrue);
    });

    test('E2E-04 [Corrupt Cache Resilience]: Malformed JSON does not crash and gets overwritten cleanly by valid fetch', () async {
      // Intentionally write corrupt garbage into cache key
      await prefs.setString(AdhanCatalogLocalDataSourceImpl.keyCatalogEnvelope, '{corrupt_garbage: !!!');
      await prefs.setString(AdhanCatalogLocalDataSourceImpl.keyCatalogJson, 'not-a-json');

      // Local data source handles corrupt data gracefully (returns null)
      final cached = await localDataSource.getCachedCatalog();
      expect(cached, isNull);

      // Spin up mock server with valid catalog
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServerBaseUrl = 'http://${mockServer!.address.address}:${mockServer!.port}';

      mockServer!.listen((HttpRequest request) {
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode(sampleValidCatalogMap));
        request.response.close();
      });

      final remoteDataSource = AdhanCatalogRemoteDataSourceImpl(client: http.Client());
      final repository = AdhanCatalogRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
        customBaseUrl: mockServerBaseUrl,
      );

      // Fetch should succeed and cleanly heal the corrupt cache
      final result = await repository.getCatalog(forceRefresh: true);
      expect(result.isRight(), isTrue);

      final healedCatalog = await localDataSource.getCachedCatalog();
      expect(healedCatalog, isNotNull);
      expect(healedCatalog!.entries.length, equals(2));
    });

    test('E2E-05 [SSRF & Security Isolation]: Dangerous path traversal object keys are rejected by validation', () {
      final invalidEntryMap = {
        'id': 'remote:malicious_entry',
        'sheikh_name': 'مهاجم',
        'audio_type': 'general',
        'display_name': 'صوت خبيث',
        'duration_seconds': 60,
        'object_key': '../../../../etc/passwd', // Path traversal attack
        'file_size_bytes': 1000,
        'sha256': 'a' * 64,
      };

      final entry = AdhanCatalogEntry.fromJson(invalidEntryMap);
      expect(entry, isNull);

      // Validate URL resolution rejects traversal
      final resolvedUrl = CatalogConfig.validateAndResolveUrl(
        '../../../../etc/passwd',
        customBaseUrl: 'https://cdn.example.com',
      );
      expect(resolvedUrl, isNull);
    });
  });
}
