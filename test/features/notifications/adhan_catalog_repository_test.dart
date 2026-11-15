import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/adhan_catalog_remote_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/errors/adhan_catalog_exceptions.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/adhan_catalog_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';

// ---------------------------------------------------------------------------
// Test Fixtures & Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _loadSampleFixture() {
  final file = File('test/fixtures/adhan_catalog_v1_sample.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> _validEntryMap({String id = 'remote:test_general'}) => {
      'id': id,
      'sheikh_name': 'الشيخ التجريبي',
      'audio_type': 'general',
      'display_name': 'أذان تجريبي',
      'duration_seconds': 65,
      'object_key': 'audio/test.mp3',
      'file_size_bytes': 1000000,
      'sha256': 'a' * 64,
    };

Map<String, dynamic> _validCatalogMap({List<Map<String, dynamic>>? entries}) => {
      'schema_version': 1,
      'generated_at': '2026-11-13T12:00:00Z',
      'entries': entries ?? [_validEntryMap()],
    };

const String kTestBaseUrl = 'https://audio.example.com';

http.Response _utf8Response(
  dynamic body,
  int statusCode, {
  Map<String, String>? headers,
}) {
  final stringBody = body is String ? body : jsonEncode(body);
  return http.Response.bytes(
    utf8.encode(stringBody),
    statusCode,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Group 1: Remote Data Source Tests
  // -------------------------------------------------------------------------
  group('AdhanCatalogRemoteDataSource', () {
    test('HTTP 200: Successfully parses JSON and captures ETag', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), equals('$kTestBaseUrl/adhan_catalog.json'));
        expect(request.headers['Accept'], equals('application/json'));
        return _utf8Response(
          _validCatalogMap(),
          200,
          headers: {'etag': '"v1-hash-abc"'},
        );
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      final response = await dataSource.fetchCatalog(
        customUrl: '$kTestBaseUrl/adhan_catalog.json',
      );

      expect(response, isA<RemoteCatalogSuccess>());
      final success = response as RemoteCatalogSuccess;
      expect(success.etag, equals('"v1-hash-abc"'));
      expect(success.json['schema_version'], equals(1));
    });

    test('HTTP 304: Returns RemoteCatalogNotModified when ETag matches', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['If-None-Match'], equals('"cached-etag"'));
        return http.Response('', 304);
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      final response = await dataSource.fetchCatalog(
        ifNoneMatch: '"cached-etag"',
        customUrl: '$kTestBaseUrl/adhan_catalog.json',
      );

      expect(response, isA<RemoteCatalogNotModified>());
    });

    test('HTTP 404: Throws CatalogNotFoundException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      expect(
        () => dataSource.fetchCatalog(customUrl: '$kTestBaseUrl/adhan_catalog.json'),
        throwsA(isA<CatalogNotFoundException>()),
      );
    });

    test('HTTP 500 / 503: Throws CatalogHttpException with status code', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 503);
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      expect(
        () => dataSource.fetchCatalog(customUrl: '$kTestBaseUrl/adhan_catalog.json'),
        throwsA(isA<CatalogHttpException>().having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('Payload > 1 MB: Throws CatalogPayloadTooLargeException', () async {
      final oversizedBytes = List<int>.filled(kCatalogJsonMaxBytes + 10, 65);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(oversizedBytes, 200);
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      expect(
        () => dataSource.fetchCatalog(customUrl: '$kTestBaseUrl/adhan_catalog.json'),
        throwsA(isA<CatalogPayloadTooLargeException>()),
      );
    });

    test('HTTP Redirect (301/302): Strictly rejects redirects to prevent SSRF', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 302, headers: {'location': 'https://other-domain.com/catalog.json'});
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      expect(
        () => dataSource.fetchCatalog(customUrl: '$kTestBaseUrl/adhan_catalog.json'),
        throwsA(isA<CatalogHttpException>().having((e) => e.statusCode, 'statusCode', 302)),
      );
    });

    test('ClientException: Throws CatalogNetworkException', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection reset by peer');
      });

      final dataSource = AdhanCatalogRemoteDataSourceImpl(client: mockClient);
      expect(
        () => dataSource.fetchCatalog(customUrl: '$kTestBaseUrl/adhan_catalog.json'),
        throwsA(isA<CatalogNetworkException>()),
      );
    });

    test('Invalid URL: Throws CatalogNetworkException', () async {
      final dataSource = AdhanCatalogRemoteDataSourceImpl();
      expect(
        () => dataSource.fetchCatalog(customUrl: 'not_a_valid_url'),
        throwsA(isA<CatalogNetworkException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 2: Local Data Source Tests (Cache & Persistence)
  // -------------------------------------------------------------------------
  group('AdhanCatalogLocalDataSource', () {
    late SharedPreferences prefs;
    late AdhanCatalogLocalDataSourceImpl localDataSource;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      localDataSource = AdhanCatalogLocalDataSourceImpl(prefs: prefs);
    });

    test('Saves and reads valid catalog correctly', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(
        sample,
        etag: '"test-etag-123"',
        timestamp: DateTime(2026, 11, 13, 10, 0),
      );

      final cached = await localDataSource.getCachedCatalog();
      expect(cached, isNotNull);
      expect(cached!.schemaVersion, equals(1));
      expect(cached.entries.length, equals(4));

      final etag = await localDataSource.getCachedEtag();
      expect(etag, equals('"test-etag-123"'));

      final time = await localDataSource.getLastCachedTime();
      expect(time, equals(DateTime(2026, 11, 13, 10, 0)));
    });

    test('Atomic Envelope: All metadata stored atomically in single key', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(sample, etag: '"atomic-etag"');

      final envelopeStr = prefs.getString(AdhanCatalogLocalDataSourceImpl.keyCatalogEnvelope);
      expect(envelopeStr, isNotNull);
      final decoded = jsonDecode(envelopeStr!) as Map<String, dynamic>;
      expect(decoded['schema_version'], equals(1));
      expect(decoded['etag'], equals('"atomic-etag"'));
      expect(decoded['catalog'], isNotNull);
    });

    test('isCacheExpired returns false when age < 24h', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      final now = DateTime.now();
      await localDataSource.saveCatalog(
        sample,
        timestamp: now.subtract(const Duration(hours: 12)),
      );

      final isExpired = await localDataSource.isCacheExpired();
      expect(isExpired, isFalse);
    });

    test('isCacheExpired returns true when age > 24h', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      final now = DateTime.now();
      await localDataSource.saveCatalog(
        sample,
        timestamp: now.subtract(const Duration(hours: 25)),
      );

      final isExpired = await localDataSource.isCacheExpired();
      expect(isExpired, isTrue);
    });

    test('isCacheExpired returns true when no cache exists', () async {
      expect(await localDataSource.isCacheExpired(), isTrue);
    });

    test('updateTimestamp updates cached timestamp without changing JSON', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      final oldTime = DateTime(2026, 11, 10, 8, 0);
      final newTime = DateTime(2026, 11, 13, 14, 0);

      await localDataSource.saveCatalog(sample, timestamp: oldTime);
      await localDataSource.updateTimestamp(timestamp: newTime);

      final updatedTime = await localDataSource.getLastCachedTime();
      expect(updatedTime, equals(newTime));

      final cached = await localDataSource.getCachedCatalog();
      expect(cached, isNotNull);
      expect(cached!.entries.length, equals(sample.entries.length));
    });

    test('Corrupted JSON in prefs returns null safely without throwing', () async {
      await prefs.setString(AdhanCatalogLocalDataSourceImpl.keyCatalogJson, '{invalid json');
      final cached = await localDataSource.getCachedCatalog();
      expect(cached, isNull);
    });

    test('clearCache removes all catalog keys', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(sample, etag: 'etag');

      await localDataSource.clearCache();
      expect(await localDataSource.getCachedCatalog(), isNull);
      expect(await localDataSource.getCachedEtag(), isNull);
      expect(await localDataSource.getLastCachedTime(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3: Repository Implementation (Orchestration & Fallbacks)
  // -------------------------------------------------------------------------
  group('AdhanCatalogRepositoryImpl', () {
    late SharedPreferences prefs;
    late AdhanCatalogLocalDataSourceImpl localDataSource;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      localDataSource = AdhanCatalogLocalDataSourceImpl(prefs: prefs);
    });

    test('Cache-first: Returns valid unexpired cached catalog without HTTP request', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(
        sample,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      );

      var networkCalled = false;
      final mockClient = MockClient((request) async {
        networkCalled = true;
        return http.Response('', 500);
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog(forceRefresh: false);

      expect(networkCalled, isFalse, reason: 'Cache is fresh, network should not be touched');
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected success'),
        (r) => expect(r.entries.length, equals(4)),
      );
    });

    test('Force refresh: Executes HTTP request even if cache is fresh', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(
        sample,
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );

      var networkCalled = false;
      final mockClient = MockClient((request) async {
        networkCalled = true;
        return _utf8Response(
          _validCatalogMap(entries: [
            _validEntryMap(id: 'remote:fresh_entry'),
          ]),
          200,
        );
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog(forceRefresh: true);

      expect(networkCalled, isTrue);
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected success'),
        (r) => expect(r.entries.first.id, equals('remote:fresh_entry')),
      );
    });

    test('HTTP 304 Not Modified: Refreshes timestamp and returns cached catalog', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      final oldTime = DateTime.now().subtract(const Duration(hours: 26));
      await localDataSource.saveCatalog(sample, etag: '"cached-etag"', timestamp: oldTime);

      final mockClient = MockClient((request) async {
        expect(request.headers['If-None-Match'], equals('"cached-etag"'));
        return http.Response('', 304);
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog();

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected success'),
        (r) => expect(r.entries.length, equals(4)),
      );

      final updatedTime = await localDataSource.getLastCachedTime();
      expect(DateTime.now().difference(updatedTime!).inSeconds, lessThan(5));
    });

    // -----------------------------------------------------------------------
    // Reservation B: Corrupt Catalog Rejection Test
    // -----------------------------------------------------------------------
    test('Reservation B: Completely corrupt catalog NEVER overwrites valid cache', () async {
      // Step 1: Establish a valid cached catalog
      final validSample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(validSample, timestamp: DateTime.now());

      // Step 2: Remote returns a catalog with entries, but ALL of them are corrupted
      final corruptRemoteJson = {
        'schema_version': 1,
        'entries': [
          {'id': 'corrupt_no_prefix', 'audio_type': 'general'},
          {'id': 'remote:bad_hash', 'audio_type': 'general', 'sha256': 'short'},
        ],
      };

      final mockClient = MockClient((request) async {
        return _utf8Response(corruptRemoteJson, 200);
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog(forceRefresh: true);

      // Must fall back to the existing valid cache!
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected fallback to cached catalog'),
        (catalog) {
          expect(catalog.entries.length, equals(4),
              reason: 'Cache must NOT be replaced with 0 entries');
        },
      );

      // Verify that SharedPreferences still holds the 4 valid entries
      final persisted = await localDataSource.getCachedCatalog();
      expect(persisted!.entries.length, equals(4));
    });

    test('Completely corrupt remote returns CatalogCorruptFailure when NO cache exists', () async {
      final corruptRemoteJson = {
        'schema_version': 1,
        'entries': [
          {'id': 'bad_entry'},
        ],
      };

      final mockClient = MockClient((request) async {
        return _utf8Response(corruptRemoteJson, 200);
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog();
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CatalogCorruptFailure>()),
        (r) => fail('Expected failure'),
      );
    });

    // -----------------------------------------------------------------------
    // Offline / Error Fallbacks
    // -----------------------------------------------------------------------
    test('Network error falls back to cached catalog if available', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(sample, timestamp: DateTime.now());

      final mockClient = MockClient((request) async {
        throw http.ClientException('Network unreachable');
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog(forceRefresh: true);

      expect(result.isRight(), isTrue, reason: 'Should fall back to cached catalog');
      result.fold(
        (l) => fail('Expected cache fallback'),
        (r) => expect(r.entries.length, equals(4)),
      );
    });

    test('Network error returns CatalogNetworkFailure when no cache exists', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('DNS failure');
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CatalogNetworkFailure>()),
        (r) => fail('Expected failure'),
      );
    });

    test('HTTP 404 returns CatalogNotFoundFailure when no cache exists', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(client: mockClient),
        localDataSource: localDataSource,
        customBaseUrl: kTestBaseUrl,
      );

      final result = await repo.getCatalog();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CatalogNotFoundFailure>()),
        (r) => fail('Expected failure'),
      );
    });

    test('Unconfigured base URL returns CatalogUnconfiguredFailure when no cache exists', () async {
      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(),
        localDataSource: localDataSource,
        customBaseUrl: null, // Unconfigured
      );

      final result = await repo.getCatalog();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CatalogUnconfiguredFailure>()),
        (r) => fail('Expected failure'),
      );
    });

    test('Unconfigured base URL returns cached catalog if cache exists', () async {
      final sample = AdhanCatalog.fromJson(_loadSampleFixture());
      await localDataSource.saveCatalog(sample, timestamp: DateTime.now());

      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(),
        localDataSource: localDataSource,
        customBaseUrl: null, // Unconfigured
      );

      final result = await repo.getCatalog();

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected cache fallback'),
        (r) => expect(r.entries.length, equals(4)),
      );
    });

    test('getCachedCatalog returns Left(CatalogCacheNotFoundFailure) when empty', () async {
      final repo = AdhanCatalogRepositoryImpl(
        remoteDataSource: AdhanCatalogRemoteDataSourceImpl(),
        localDataSource: localDataSource,
      );

      final result = await repo.getCachedCatalog();
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CatalogCacheNotFoundFailure>()),
        (r) => fail('Expected failure'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 4: Reservation A: Strict URL & SSRF Validation Tests
  // -------------------------------------------------------------------------
  group('Reservation A: Strict URL & SSRF Validation', () {
    test('Rejects non-HTTPS schemes (e.g. http://) on non-localhost domains', () {
      final resolved = CatalogConfig.validateAndResolveUrl(
        'audio/test.mp3',
        customBaseUrl: 'http://insecure.example.com',
      );
      expect(resolved, isNull, reason: 'Plain HTTP must be strictly rejected');
    });

    test('Allows HTTP only on localhost / 127.0.0.1 / 10.0.2.2 for dev/test', () {
      final resolved = CatalogConfig.validateAndResolveUrl(
        'audio/test.mp3',
        customBaseUrl: 'http://localhost:8080',
      );
      expect(resolved, equals('http://localhost:8080/audio/test.mp3'));
    });

    test('SSRF Guard: Rejects absolute URLs attempting to bypass base host', () {
      expect(
        CatalogConfig.validateAndResolveUrl(
          'https://attacker.com/evil.mp3',
          customBaseUrl: kTestBaseUrl,
        ),
        isNull,
        reason: 'Absolute URL in objectKey must be rejected',
      );
      expect(
        CatalogConfig.validateAndResolveUrl(
          '//attacker.com/evil.mp3',
          customBaseUrl: kTestBaseUrl,
        ),
        isNull,
        reason: 'Protocol-relative URL must be rejected',
      );
      expect(
        CatalogConfig.validateAndResolveUrl(
          'ftp://files.example.com/audio.mp3',
          customBaseUrl: kTestBaseUrl,
        ),
        isNull,
      );
    });

    test('Rejects path traversal via .. or backslash', () {
      expect(
        CatalogConfig.validateAndResolveUrl(
          '../secrets/key.mp3',
          customBaseUrl: kTestBaseUrl,
        ),
        isNull,
      );
      expect(
        CatalogConfig.validateAndResolveUrl(
          r'audio\sub\file.mp3',
          customBaseUrl: kTestBaseUrl,
        ),
        isNull,
        reason: 'Backslashes must be rejected',
      );
    });

    test('Valid relative key resolves cleanly with matching host and HTTPS', () {
      final resolved = CatalogConfig.validateAndResolveUrl(
        'audio/mishary_alafasy_fajr.mp3',
        customBaseUrl: 'https://cdn.hafizalahd.com',
      );
      expect(
        resolved,
        equals('https://cdn.hafizalahd.com/audio/mishary_alafasy_fajr.mp3'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 5: Reservation B: AdhanCatalog Metadata & Partial Validity Flags
  // -------------------------------------------------------------------------
  group('Reservation B: AdhanCatalog Metadata & Partial Validity', () {
    test('Fully valid catalog sets isFullyValid = true', () {
      final catalog = AdhanCatalog.fromJson(_validCatalogMap(entries: [
        _validEntryMap(id: 'remote:e1'),
        _validEntryMap(id: 'remote:e2'),
      ]));

      expect(catalog.rawEntriesCount, equals(2));
      expect(catalog.droppedEntriesCount, equals(0));
      expect(catalog.isFullyValid, isTrue);
      expect(catalog.isPartiallyValid, isFalse);
      expect(catalog.isCompletelyCorrupt, isFalse);
      expect(catalog.isEmpty, isFalse);
    });

    test('Partially valid catalog records dropped count and sets isPartiallyValid = true', () {
      final catalog = AdhanCatalog.fromJson(_validCatalogMap(entries: [
        _validEntryMap(id: 'remote:e1'),
        {'id': 'corrupt_no_prefix'}, // dropped
        _validEntryMap(id: 'remote:e2'),
      ]));

      expect(catalog.rawEntriesCount, equals(3));
      expect(catalog.droppedEntriesCount, equals(1));
      expect(catalog.entries.length, equals(2));
      expect(catalog.isFullyValid, isFalse);
      expect(catalog.isPartiallyValid, isTrue);
      expect(catalog.isCompletelyCorrupt, isFalse);
    });

    test('Completely corrupt catalog sets isCompletelyCorrupt = true', () {
      final catalog = AdhanCatalog.fromJson(_validCatalogMap(entries: [
        {'id': 'corrupt_1'},
        {'id': 'corrupt_2'},
      ]));

      expect(catalog.rawEntriesCount, equals(2));
      expect(catalog.droppedEntriesCount, equals(2));
      expect(catalog.entries, isEmpty);
      expect(catalog.isCompletelyCorrupt, isTrue);
      expect(catalog.isFullyValid, isFalse);
      expect(catalog.isPartiallyValid, isFalse);
    });

    test('Structurally empty catalog sets isEmpty = true and isCompletelyCorrupt = false', () {
      final catalog = AdhanCatalog.fromJson(_validCatalogMap(entries: []));

      expect(catalog.rawEntriesCount, equals(0));
      expect(catalog.droppedEntriesCount, equals(0));
      expect(catalog.entries, isEmpty);
      expect(catalog.isEmpty, isTrue);
      expect(catalog.isCompletelyCorrupt, isFalse);
    });
  });
}

