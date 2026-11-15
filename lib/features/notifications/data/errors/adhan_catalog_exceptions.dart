/// Exceptions thrown within the remote catalog data sources.
abstract class AdhanCatalogException implements Exception {
  final String message;
  const AdhanCatalogException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class CatalogHttpException extends AdhanCatalogException {
  final int statusCode;
  const CatalogHttpException(this.statusCode, [String message = 'HTTP error'])
      : super('$message (HTTP $statusCode)');
}

class CatalogNotFoundException extends AdhanCatalogException {
  const CatalogNotFoundException([super.message = 'Catalog not found (404)']);
}

class CatalogPayloadTooLargeException extends AdhanCatalogException {
  const CatalogPayloadTooLargeException([
    super.message = 'Catalog payload exceeds maximum allowed size (1 MB)',
  ]);
}

class CatalogNetworkException extends AdhanCatalogException {
  const CatalogNetworkException([super.message = 'Network connectivity or timeout error']);
}

class CatalogStorageException extends AdhanCatalogException {
  const CatalogStorageException([super.message = 'Storage or serialization error']);
}

