import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/errors/adhan_catalog_exceptions.dart';

/// Represents the raw result of a remote catalog HTTP GET request.
sealed class RemoteCatalogResponse {
  const RemoteCatalogResponse();
}

/// HTTP 200 with freshly fetched JSON map and optional ETag header.
class RemoteCatalogSuccess extends RemoteCatalogResponse {
  final Map<String, dynamic> json;
  final String? etag;

  const RemoteCatalogSuccess(this.json, {this.etag});
}

/// HTTP 304 Not Modified indicating local cached copy matches the server ETag.
class RemoteCatalogNotModified extends RemoteCatalogResponse {
  const RemoteCatalogNotModified();
}

/// Remote data source contract for fetching the remote adhan audio catalog.
abstract class BaseAdhanCatalogRemoteDataSource {
  /// Executes a public HTTP GET request to retrieve the catalog JSON.
  ///
  /// - Passes `If-None-Match: [ifNoneMatch]` if supplied.
  /// - Times out after [kCatalogFetchTimeout] (15 seconds).
  /// - Rejects payloads larger than [kCatalogJsonMaxBytes] (1 MB).
  /// - Throws specific [AdhanCatalogException] subclasses upon failures.
  Future<RemoteCatalogResponse> fetchCatalog({
    String? ifNoneMatch,
    String? customUrl,
  });
}

class AdhanCatalogRemoteDataSourceImpl implements BaseAdhanCatalogRemoteDataSource {
  final http.Client client;

  AdhanCatalogRemoteDataSourceImpl({http.Client? client})
      : client = client ?? http.Client();

  @override
  Future<RemoteCatalogResponse> fetchCatalog({
    String? ifNoneMatch,
    String? customUrl,
  }) async {
    final targetUrl = customUrl ?? CatalogConfig.catalogJsonUrl;
    final uri = Uri.tryParse(targetUrl);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const CatalogNetworkException('Invalid or unconfigured catalog URL');
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        'If-None-Match': ifNoneMatch,
    };

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(headers)
        ..followRedirects = false; // Security: Disallow automatic silent redirects

      final streamedResponse =
          await client.send(request).timeout(kCatalogFetchTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      // Explicitly reject unexpected redirects (prevents cross-host SSRF or HTTPS downgrade)
      if (response.isRedirect ||
          response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        throw CatalogHttpException(
          response.statusCode,
          'HTTP redirects are strictly disallowed for catalog resources',
        );
      }

      if (response.statusCode == 304) {
        return const RemoteCatalogNotModified();
      }

      if (response.statusCode == 404) {
        throw const CatalogNotFoundException();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogHttpException(
          response.statusCode,
          'Server returned HTTP status ${response.statusCode}',
        );
      }

      if (response.bodyBytes.length > kCatalogJsonMaxBytes) {
        throw const CatalogPayloadTooLargeException();
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON map at root of catalog response');
      }

      final etag = response.headers['etag'];

      return RemoteCatalogSuccess(decoded, etag: etag);
    } on TimeoutException {
      throw const CatalogNetworkException('Catalog request timed out after 15 seconds');
    } on SocketException catch (e) {
      throw CatalogNetworkException('Network connection failed: ${e.message}');
    } on http.ClientException catch (e) {
      throw CatalogNetworkException('HTTP client error: ${e.message}');
    } on AdhanCatalogException {
      rethrow;
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw CatalogNetworkException('Unexpected network error: $e');
    }
  }
}

