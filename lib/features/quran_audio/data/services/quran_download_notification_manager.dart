import 'dart:async';
import '../../../quran/data/datasources/surah_names.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/audio_reciter.dart';
import '../../domain/entities/download_progress.dart';
import '../../domain/entities/quran_download_queue_progress.dart';
import '../../domain/entities/quran_download_queue_status.dart';
import '../../domain/services/base_quran_download_notification_service.dart';
import '../datasources/quran_audio_local_data_source.dart';
import 'quran_audio_queue_service.dart';

/// Internal payload container for notification dispatch.
class _NotificationPayload {
  final String title;
  final String body;
  final double? progressRatio;
  final bool isOngoing;
  final bool isIndeterminate;
  final bool isTerminal;
  final bool isError;

  const _NotificationPayload({
    required this.title,
    required this.body,
    this.progressRatio,
    this.isOngoing = true,
    this.isIndeterminate = false,
    this.isTerminal = false,
    this.isError = false,
  });
}

/// Serialized sender managing rate-limiting (throttling), session guarding, and trailing flushes.
class _ThrottledSender {
  final BaseQuranDownloadNotificationService notificationService;
  final int notificationId;
  final Duration window;

  DateTime? _lastUpdateTime;
  Timer? _pendingTimer;
  _NotificationPayload? _pendingPayload;
  String? _activeSessionId;

  _ThrottledSender({
    required this.notificationService,
    required this.notificationId,
    this.window = const Duration(milliseconds: 750),
  });

  String? get activeSessionId => _activeSessionId;

  void startSession(String sessionId) {
    _cancelPendingTimer();
    _activeSessionId = sessionId;
    _lastUpdateTime = null;
    _pendingPayload = null;
  }

  void endSession(String sessionId) {
    if (_activeSessionId == sessionId) {
      _cancelPendingTimer();
      _activeSessionId = null;
      _pendingPayload = null;
      _lastUpdateTime = null;
    }
  }

  void _cancelPendingTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  Future<void> sendImmediate({
    required String sessionId,
    required _NotificationPayload payload,
  }) async {
    if (_activeSessionId != sessionId) return; // Stale session guard (C4)
    _cancelPendingTimer();
    _pendingPayload = null;
    _lastUpdateTime = DateTime.now();
    await _dispatch(payload);
  }

  void sendThrottled({
    required String sessionId,
    required _NotificationPayload payload,
  }) {
    if (_activeSessionId != sessionId) return; // Stale session guard (C4)

    _pendingPayload = payload;
    final now = DateTime.now();

    if (_lastUpdateTime == null || now.difference(_lastUpdateTime!) >= window) {
      // First event or window elapsed, dispatch immediately
      _cancelPendingTimer();
      _lastUpdateTime = now;
      final toSend = _pendingPayload!;
      _pendingPayload = null;
      _dispatch(toSend);
    } else {
      // Schedule trailing flush if not already scheduled
      if (_pendingTimer == null) {
        final remaining = window - now.difference(_lastUpdateTime!);
        _pendingTimer = Timer(remaining, () {
          _pendingTimer = null;
          if (_activeSessionId != sessionId) return;
          if (_pendingPayload != null) {
            _lastUpdateTime = DateTime.now();
            final toSend = _pendingPayload!;
            _pendingPayload = null;
            _dispatch(toSend);
          }
        });
      }
    }
  }

  Future<void> _dispatch(_NotificationPayload payload) async {
    if (payload.isTerminal) {
      await notificationService.showTerminalNotification(
        id: notificationId,
        title: payload.title,
        body: payload.body,
        isError: payload.isError,
      );
    } else {
      await notificationService.showProgressNotification(
        id: notificationId,
        title: payload.title,
        body: payload.body,
        progressRatio: payload.progressRatio,
        isOngoing: payload.isOngoing,
        isIndeterminate: payload.isIndeterminate,
      );
    }
  }
}

/// Orchestrates download notifications independently of the Presentation layer (C2).
///
/// Responsibilities:
/// 1. Subscribes directly to [QuranAudioQueueService.progressStream] and single-Surah streams.
/// 2. Isolates operations via monotonic session tokens (C4) to eliminate race conditions and stale events.
/// 3. Applies a strict 750ms throttling window with coalescing and trailing flush (C3).
/// 4. Ensures terminal notifications are posted only upon complete verified storage promotion (C7).
/// 5. Formats all messages canonically in Arabic.
class QuranDownloadNotificationManager {
  final BaseQuranDownloadNotificationService notificationService;
  final BaseQuranAudioLocalDataSource localDataSource;

  late final _ThrottledSender _singleSurahSender;
  late final _ThrottledSender _queueSender;

  StreamSubscription<QuranDownloadQueueProgress>? _queueSubscription;
  StreamSubscription<DownloadProgress>? _singleSurahSubscription;

  int _sessionSequence = 0;

  QuranDownloadNotificationManager({
    required this.notificationService,
    required this.localDataSource,
    Duration throttleWindow = const Duration(milliseconds: 750),
  }) {
    _singleSurahSender = _ThrottledSender(
      notificationService: notificationService,
      notificationId: BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId,
      window: throttleWindow,
    );
    _queueSender = _ThrottledSender(
      notificationService: notificationService,
      notificationId: BaseQuranDownloadNotificationService.kFullQuranDownloadNotificationId,
      window: throttleWindow,
    );
  }

  String _nextSessionId(String prefix) {
    _sessionSequence++;
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_$_sessionSequence';
  }

  // ---------------------------------------------------------------------------
  // Full Quran Queue Binding
  // ---------------------------------------------------------------------------

  /// Binds directly to the [QuranAudioQueueService] stream for decoupled notifications.
  void bindQueueService(QuranAudioQueueService queueService) {
    _queueSubscription?.cancel();
    _queueSubscription = queueService.progressStream.listen((progress) {
      handleQueueProgress(progress);
    });
  }

  /// Processes a [QuranDownloadQueueProgress] update from the queue engine.
  Future<void> handleQueueProgress(QuranDownloadQueueProgress progress) async {
    final status = progress.status;

    if (status.isCancelled) {
      if (_queueSender.activeSessionId != null) {
        _queueSender.endSession(_queueSender.activeSessionId!);
      }
      await notificationService.dismissQueueNotification();
      return;
    }

    final sessionId = progress.queueId;
    if (_queueSender.activeSessionId != sessionId) {
      _queueSender.startSession(sessionId);
    }

    final reciterName = await _resolveReciterName(progress.reciterId);
    final title = 'تحميل المصحف كاملاً — $reciterName';

    if (status == QuranDownloadQueueStatus.pending) {
      await _queueSender.sendImmediate(
        sessionId: sessionId,
        payload: _NotificationPayload(
          title: title,
          body: 'جاري تهيئة طابور التنزيل...',
          isOngoing: true,
          isIndeterminate: true,
        ),
      );
      return;
    }

    if (status.isPaused) {
      final pctText = progress.totalExpectedBytes != null && progress.totalExpectedBytes! > 0
          ? ' (${(progress.aggregateRatio * 100).toInt()}%)'
          : '';
      await _queueSender.sendImmediate(
        sessionId: sessionId,
        payload: _NotificationPayload(
          title: '$title (متوقف مؤقتاً)',
          body: 'تم تحميل ${progress.completedItems} من 114 سورة$pctText',
          progressRatio: progress.aggregateRatio,
          isOngoing: false, // User can dismiss when paused (C1/UX)
          isIndeterminate: progress.totalExpectedBytes == null,
        ),
      );
      return;
    }

    if (status.isCompleted) {
      await _queueSender.sendImmediate(
        sessionId: sessionId,
        payload: _NotificationPayload(
          title: 'اكتمل تحميل المصحف كاملاً',
          body: 'جميع سور القرآن الكريم (114 سورة) بصوت $reciterName جاهزة للاستماع دون إنترنت.',
          isTerminal: true,
          isError: false,
        ),
      );
      _queueSender.endSession(sessionId);
      return;
    }

    if (status.isFailed) {
      final errorMsg = formatUserFriendlyAudioError(progress.lastError);
      await _queueSender.sendImmediate(
        sessionId: sessionId,
        payload: _NotificationPayload(
          title: 'توقف تحميل المصحف كاملاً',
          body: errorMsg,
          isTerminal: true,
          isError: true,
        ),
      );
      _queueSender.endSession(sessionId);
      return;
    }

    if (status.isRunning) {
      final activeSurah = progress.activeSurahNumber;
      final activeSurahName = activeSurah != null ? ' • سورة ${getSurahName(activeSurah)}' : '';

      final bool isDeterminate = progress.totalExpectedBytes != null && progress.totalExpectedBytes! > 0;
      final String body;

      if (isDeterminate) {
        final pct = (progress.aggregateRatio * 100).toInt();
        body = 'تم تحميل ${progress.completedItems} من 114 سورة ($pct%)$activeSurahName';
      } else {
        body = 'تم تحميل ${progress.completedItems} من 114 سورة$activeSurahName';
      }

      _queueSender.sendThrottled(
        sessionId: sessionId,
        payload: _NotificationPayload(
          title: title,
          body: body,
          progressRatio: isDeterminate ? progress.aggregateRatio : null,
          isOngoing: true,
          isIndeterminate: !isDeterminate,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Single Surah Tracking
  // ---------------------------------------------------------------------------

  /// Tracks an individual Surah download stream until it completes, pauses, fails, or cancels.
  StreamSubscription<DownloadProgress> trackSingleSurahDownload({
    required int surahNumber,
    required String reciterId,
    String? reciterName,
    required Stream<DownloadProgress> progressStream,
  }) {
    _singleSurahSubscription?.cancel();

    final sessionId = _nextSessionId('single_${reciterId}_$surahNumber');
    _singleSurahSender.startSession(sessionId);

    final surahName = getSurahName(surahNumber);
    final fallbackReciterName = reciterName ?? _resolveReciterNameSync(reciterId);

    // Initial immediate notification
    _singleSurahSender.sendImmediate(
      sessionId: sessionId,
      payload: _NotificationPayload(
        title: 'سورة $surahName — $fallbackReciterName',
        body: 'بدء تحميل السورة...',
        isOngoing: true,
        isIndeterminate: true,
      ),
    );

    _singleSurahSubscription = progressStream.listen((progress) {
      _handleSingleSurahProgress(
        sessionId: sessionId,
        surahNumber: surahNumber,
        surahName: surahName,
        reciterName: fallbackReciterName,
        progress: progress,
      );
    });

    return _singleSurahSubscription!;
  }

  void _handleSingleSurahProgress({
    required String sessionId,
    required int surahNumber,
    required String surahName,
    required String reciterName,
    required DownloadProgress progress,
  }) {
    if (_singleSurahSender.activeSessionId != sessionId) return;

    final title = 'سورة $surahName — $reciterName';

    switch (progress.status) {
      case AudioDownloadStatus.idle:
      case AudioDownloadStatus.preparing:
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: title,
            body: 'بدء تحميل السورة...',
            isOngoing: true,
            isIndeterminate: true,
          ),
        );
        break;

      case AudioDownloadStatus.downloading:
        final ratio = progress.progressRatio;
        final isKnown = ratio > 0.0;
        final pct = (ratio * 100).toInt();
        final downloadedMb = (progress.downloadedBytes / (1024 * 1024)).toStringAsFixed(1);

        String body;
        if (progress.expectedTotalBytes != null && progress.expectedTotalBytes! > 0) {
          final totalMb = (progress.expectedTotalBytes! / (1024 * 1024)).toStringAsFixed(1);
          body = 'جاري التحميل... $pct% ($downloadedMb / $totalMb ميجابايت)';
        } else {
          body = 'جاري التحميل... ($downloadedMb ميجابايت)';
        }

        _singleSurahSender.sendThrottled(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: title,
            body: body,
            progressRatio: ratio,
            isOngoing: true,
            isIndeterminate: !isKnown,
          ),
        );
        break;

      case AudioDownloadStatus.verifying:
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: title,
            body: 'جاري التحقق من سلامة الملف الصوتي...',
            isOngoing: true,
            isIndeterminate: true,
          ),
        );
        break;

      case AudioDownloadStatus.promoting:
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: title,
            body: 'جاري حفظ السورة محلياً...',
            isOngoing: true,
            isIndeterminate: true,
          ),
        );
        break;

      case AudioDownloadStatus.paused:
        final ratio = progress.progressRatio;
        final pct = (ratio > 0.0) ? ' (${(ratio * 100).toInt()}%)' : '';
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: title,
            body: 'التحميل متوقف مؤقتاً$pct',
            progressRatio: ratio,
            isOngoing: false,
            isIndeterminate: false,
          ),
        );
        break;

      case AudioDownloadStatus.completed:
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: 'اكتمل التحميل',
            body: 'تم تحميل سورة $surahName بصوت $reciterName بنجاح.',
            isTerminal: true,
            isError: false,
          ),
        );
        _singleSurahSender.endSession(sessionId);
        break;

      case AudioDownloadStatus.failed:
        final errorMsg = formatUserFriendlyAudioError(progress.lastError);
        _singleSurahSender.sendImmediate(
          sessionId: sessionId,
          payload: _NotificationPayload(
            title: 'تعذر تحميل سورة $surahName',
            body: errorMsg,
            isTerminal: true,
            isError: true,
          ),
        );
        _singleSurahSender.endSession(sessionId);
        break;

      case AudioDownloadStatus.cancelled:
      case AudioDownloadStatus.missing:
      case AudioDownloadStatus.corrupted:
        _singleSurahSender.endSession(sessionId);
        notificationService.dismissSingleSurahNotification();
        break;
    }
  }

  /// Cancels any active single-Surah tracking session and dismisses its notification.
  Future<void> cancelSingleSurahSession() async {
    _singleSurahSubscription?.cancel();
    _singleSurahSubscription = null;
    if (_singleSurahSender.activeSessionId != null) {
      _singleSurahSender.endSession(_singleSurahSender.activeSessionId!);
    }
    await notificationService.dismissSingleSurahNotification();
  }

  /// Cancels any active full-Quran queue tracking session and dismisses its notification.
  Future<void> cancelQueueSession() async {
    if (_queueSender.activeSessionId != null) {
      _queueSender.endSession(_queueSender.activeSessionId!);
    }
    await notificationService.dismissQueueNotification();
  }

  // ---------------------------------------------------------------------------
  // Reciter Name Resolution
  // ---------------------------------------------------------------------------

  Future<String> _resolveReciterName(String reciterId) async {
    try {
      final cached = await localDataSource.getCachedReciters();
      if (cached != null) {
        for (final r in cached) {
          if (r.id == reciterId) return r.displayName;
        }
      }
    } catch (_) {}
    return _resolveReciterNameSync(reciterId);
  }

  String _resolveReciterNameSync(String reciterId) {
    for (final r in AudioReciter.kDefaultReciters) {
      if (r.id == reciterId) return r.displayName;
    }
    return 'القارئ';
  }

  void dispose() {
    _queueSubscription?.cancel();
    _singleSurahSubscription?.cancel();
    if (_singleSurahSender.activeSessionId != null) {
      _singleSurahSender.endSession(_singleSurahSender.activeSessionId!);
    }
    if (_queueSender.activeSessionId != null) {
      _queueSender.endSession(_queueSender.activeSessionId!);
    }
  }
}

/// Standardized user-friendly error formatting shared across UI and notifications.
String formatUserFriendlyAudioError(String? rawError) {
  if (rawError == null || rawError.trim().isEmpty) {
    return 'تعذر إتمام التحميل. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
  }

  final lower = rawError.toLowerCase();

  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('clientexception') ||
      lower.contains('handshakeexception') ||
      lower.contains('timeoutexception') ||
      lower.contains('timed out')) {
    return 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
  }

  if (lower.contains('no space left') || lower.contains('enospc') || lower.contains('disk full')) {
    return 'المساحة التخزينية على جهازك غير كافية لإتمام التحميل.';
  }
  if (lower.contains('permission denied') || lower.contains('eacces') || lower.contains('access denied')) {
    return 'تعذر حفظ الملف بسبب نقص صلاحيات التخزين على الجهاز.';
  }

  if (lower.contains('404') || lower.contains('not found')) {
    return 'الملف الصوتي غير متوفر على الخادم لهذا القارئ.';
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503') || lower.contains('504')) {
    return 'الخادم غير متاح حاليًا. يرجى المحاولة في وقت لاحق.';
  }

  if (lower.contains('stream truncated') || lower.contains('checksum mismatch') || lower.contains('corrupt')) {
    return 'فشل التحقق من اكتمال الملف الصوتي. يرجى إعادة المحاولة.';
  }

  final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(rawError);
  final hasExceptionKeywords = lower.contains('exception') ||
      lower.contains('failed') ||
      lower.contains('errno') ||
      lower.contains('http') ||
      lower.contains('os error');

  if (hasArabic && !hasExceptionKeywords) {
    return rawError;
  }

  return 'تعذر إتمام التحميل. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
}
