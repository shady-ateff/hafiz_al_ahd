import 'package:equatable/equatable.dart';

/// Utility to classify HTTP validators (ETag and Last-Modified) according to RFC 9110 rules.
class HttpStrongValidator {
  const HttpStrongValidator._();

  /// Evaluates whether an ETag qualifies as a Strong Validator according to RFC 9110 §8.8.3.
  ///
  /// - Strong ETags MUST start with a double quote `"` and NOT start with `W/` or `w/`.
  /// - Weak ETags (e.g. `W/"abc"`) are strictly non-strong and return `false`.
  static bool isStrongEtag(String? etag) {
    if (etag == null) return false;
    final trimmed = etag.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('W/') || trimmed.startsWith('w/')) return false;
    return trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2;
  }

  /// Evaluates whether a Last-Modified header qualifies as a Strong Validator
  /// according to RFC 9110 §8.8.2.2.
  ///
  /// RFC 9110 Rule: An origin Date header must be present, and:
  /// `Date - Last-Modified >= 1 second` using origin server clock (NEVER local device clock).
  static bool isStrongLastModified({
    required String? lastModifiedHeader,
    required String? originDateHeader,
  }) {
    if (lastModifiedHeader == null || originDateHeader == null) return false;
    final lastModified = _parseHttpDate(lastModifiedHeader);
    final originDate = _parseHttpDate(originDateHeader);
    if (lastModified == null || originDate == null) return false;

    // Date - Last-Modified >= 1 second
    return originDate.difference(lastModified).inSeconds >= 1;
  }

  /// Evaluates whether an opaque validator token qualifies as an authenticated strong validator.
  static bool isCertifiedStrongValidator(String? validator) {
    if (validator == null) return false;
    final trimmed = validator.trim();
    if (trimmed.isEmpty) return false;

    // Direct strong ETag
    if (isStrongEtag(trimmed)) return true;

    // Certified strong Last-Modified token format: "STRONG_LM:<origin_date>|<last_modified>"
    if (trimmed.startsWith('STRONG_LM:')) {
      final payload = trimmed.substring('STRONG_LM:'.length);
      final parts = payload.split('|');
      if (parts.length == 2) {
        return isStrongLastModified(
          originDateHeader: parts[0],
          lastModifiedHeader: parts[1],
        );
      }
    }
    return false;
  }

  static DateTime? _parseHttpDate(String raw) {
    try {
      final trimmed = raw.trim();
      return DateTime.tryParse(trimmed) ?? _parseRfc1123(trimmed);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseRfc1123(String dateStr) {
    try {
      final parts = dateStr.split(' ');
      if (parts.length >= 5) {
        final day = parts[1].padLeft(2, '0');
        final monthStr = parts[2].toLowerCase();
        final year = parts[3];
        final time = parts[4];
        final months = {
          'jan': '01',
          'feb': '02',
          'mar': '03',
          'apr': '04',
          'may': '05',
          'jun': '06',
          'jul': '07',
          'aug': '08',
          'sep': '09',
          'oct': '10',
          'nov': '11',
          'dec': '12',
        };
        final month = months[monthStr];
        if (month != null) {
          return DateTime.tryParse('$year-$month-$day $time Z');
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Represents the cryptographic and metadata identity of a remote audio resource.
///
/// Used to guarantee that an interrupted staging file is never resumed against
/// a changed or mismatched remote origin.
class DownloadResourceIdentity extends Equatable {
  /// The target HTTP request URL for the Surah audio stream/file.
  final String requestUrl;

  /// The previously recorded URL from the initiated download record.
  final String recordedUrl;

  /// The target Surah number (1 to 114).
  final int surahNumber;

  /// The recorded Surah number from the initiated download record.
  final int recordedSurahNumber;

  /// The target Reciter ID.
  final String reciterId;

  /// The recorded Reciter ID from the initiated download record.
  final String recordedReciterId;

  /// The remote HTTP response strong validator (Strong ETag or RFC 9110 Strong Last-Modified token).
  final String? responseStrongValidator;

  /// The recorded strong validator from the prior response headers.
  final String? recordedStrongValidator;

  const DownloadResourceIdentity({
    required this.requestUrl,
    required this.recordedUrl,
    required this.surahNumber,
    required this.recordedSurahNumber,
    required this.reciterId,
    required this.recordedReciterId,
    this.responseStrongValidator,
    this.recordedStrongValidator,
  });

  /// Evaluates whether the remote resource is proven to be the exact same file.
  ///
  /// Resumption is strictly permitted ONLY when this evaluates to true.
  /// Must satisfy URL, Surah, Reciter match AND validator equality AND validator strength certification.
  bool get isIdenticalResource {
    if (requestUrl.trim() != recordedUrl.trim() ||
        surahNumber != recordedSurahNumber ||
        reciterId.trim() != recordedReciterId.trim() ||
        responseStrongValidator == null ||
        recordedStrongValidator == null ||
        responseStrongValidator != recordedStrongValidator) {
      return false;
    }

    // Must be classified as an authenticated Strong Validator (RFC 9110)
    return HttpStrongValidator.isCertifiedStrongValidator(responseStrongValidator);
  }

  @override
  List<Object?> get props => [
        requestUrl,
        recordedUrl,
        surahNumber,
        recordedSurahNumber,
        reciterId,
        recordedReciterId,
        responseStrongValidator,
        recordedStrongValidator,
      ];
}
