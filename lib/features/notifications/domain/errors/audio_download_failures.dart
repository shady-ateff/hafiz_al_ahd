import 'package:hafiz_al_ahd/core/errors/failure.dart';

/// Base class for all audio download and verification failures.
abstract class AudioDownloadFailure extends Failure {
  AudioDownloadFailure({required super.message});
}

/// Network timeout or disconnection during audio chunk streaming.
class AudioDownloadNetworkFailure extends AudioDownloadFailure {
  AudioDownloadNetworkFailure({
    super.message = 'انقطع الاتصال بالإنترنت أثناء تنزيل ملف الصوت. يرجى إعادة المحاولة.',
  });
}

/// Downloaded physical bytes do not match expectedSizeBytes from catalog metadata.
class AudioDownloadSizeMismatchFailure extends AudioDownloadFailure {
  final int actualBytes;
  final int expectedBytes;

  AudioDownloadSizeMismatchFailure({
    required this.actualBytes,
    required this.expectedBytes,
  }) : super(
          message:
              'حجم الملف الذي تم تنزيله ($actualBytes بايت) غير مطابق للحجم المتوقع ($expectedBytes بايت).',
        );
}

/// Audio file exceeds the absolute hard ceiling of 30 MB.
class AudioDownloadOversizedFailure extends AudioDownloadFailure {
  final int bytes;
  AudioDownloadOversizedFailure({required this.bytes})
      : super(
          message: 'تجاوز حجم ملف الصوت الحد الأقصى المسموح به (30 ميجابايت).',
        );
}

/// Calculated SHA-256 digest of the downloaded file does not match catalog metadata.
class AudioDownloadIntegrityFailure extends AudioDownloadFailure {
  final String actualHash;
  final String expectedHash;

  AudioDownloadIntegrityFailure({
    required this.actualHash,
    required this.expectedHash,
  }) : super(
          message: 'فشل التحقق من صحة الملف الرقمية (SHA-256). تم إلغاء حفظ الملف لحمايتك.',
        );
}

/// Failed to write to temporary file or atomically promote to private app storage.
class AudioDownloadStorageFailure extends AudioDownloadFailure {
  AudioDownloadStorageFailure({
    super.message = 'تعذر تخزين ملف الصوت على مساحة الهاتف المحلية. تأكد من توفر مساحة كافية.',
  });
}

/// Download was intentionally cancelled by user action.
class AudioDownloadCancelledFailure extends AudioDownloadFailure {
  AudioDownloadCancelledFailure({
    super.message = 'تم إلغاء تنزيل ملف الصوت.',
  });
}

/// A download is already running and concurrency policy enforces single-task execution.
class AudioDownloadConcurrencyFailure extends AudioDownloadFailure {
  AudioDownloadConcurrencyFailure({
    super.message = 'يوجد تنزيل آخر قيد التنفيذ حالياً. يرجى الانتظار حتى اكتماله.',
  });
}

/// Resolved download URL was rejected by security guards (SSRF, non-HTTPS, or host mismatch).
class AudioDownloadSecurityFailure extends AudioDownloadFailure {
  AudioDownloadSecurityFailure({
    super.message = 'عنوان تحميل الصوت غير آمن أو غير موثوق.',
  });
}

/// Download was rejected by the admission guard because projected remote cache usage exceeds the 150 MiB quota.
class AudioDownloadQuotaExceededFailure extends AudioDownloadFailure {
  final int requiredBytes;
  final int availableBytes;

  AudioDownloadQuotaExceededFailure({
    required this.requiredBytes,
    required this.availableBytes,
  }) : super(
          message:
              'لا توجد مساحة كافية في كاش الأصوات السحابية (المتاح: ${(availableBytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت، المطلوب: ${(requiredBytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت). يرجى حذف بعض الأصوات السحابية السابقة.',
        );
}

