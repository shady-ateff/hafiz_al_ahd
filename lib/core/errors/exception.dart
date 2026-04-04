// أخطاء السيرفر (لو بتجيب داتا من API)
class ServerException implements Exception {}

// خطأ الكاش (ده اللي الكومبايلر بيشتكي منه دلوقتي)
class CacheException implements Exception {}

// خطأ اللوكيشن (لو الـ GPS مقفول مثلاً)
class LocationException implements Exception {}


class NetworkException implements Exception {}
