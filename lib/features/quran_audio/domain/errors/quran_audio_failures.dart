import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';

/// Base class for all failures originating in the Quran Audio subsystem.
abstract class QuranAudioFailure extends Failure with Equatable {
  QuranAudioFailure({required super.message});

  @override
  List<Object?> get props => [message];
}

/// Network failure during audio metadata retrieval or streaming.
class QuranAudioNetworkFailure extends QuranAudioFailure {
  QuranAudioNetworkFailure({
    super.message = 'تعذر الاتصال بالخادم، يرجى التحقق من اتصال الإنترنت',
  });
}

/// Audio resource or metadata not found (e.g. 404).
class QuranAudioNotFoundFailure extends QuranAudioFailure {
  QuranAudioNotFoundFailure({
    super.message = 'التسجيل الصوتي أو بيانات التوقيت غير متوفرة',
  });
}

/// Local storage failure (insufficient disk space, write error, or missing file).
class QuranAudioStorageFailure extends QuranAudioFailure {
  QuranAudioStorageFailure({
    super.message = 'حدث خطأ في التخزين المحلي للملفات الصوتية',
  });
}

/// Corrupt audio file or invalid checksum.
class QuranAudioCorruptFailure extends QuranAudioFailure {
  QuranAudioCorruptFailure({
    super.message = 'الملف الصوتي تالف أو لا يتطابق مع الحجم المعتمد',
  });
}

/// Security or path containment violation.
class QuranAudioSecurityFailure extends QuranAudioFailure {
  QuranAudioSecurityFailure({
    super.message = 'تم حظر الوصول إلى مسار تخزين غير آمن',
  });
}

/// Download was intentionally cancelled by user or coordinator.
class QuranAudioCancelledFailure extends QuranAudioFailure {
  QuranAudioCancelledFailure({
    super.message = 'تم إلغاء عملية التنزيل',
  });
}

/// Audio player initialization or playback engine failure.
class QuranAudioPlaybackFailure extends QuranAudioFailure {
  QuranAudioPlaybackFailure({
    super.message = 'حدث خطأ أثناء تشغيل الملف الصوتي',
  });
}
