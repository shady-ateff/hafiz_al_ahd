import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/datasources/quran_audio_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_download_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/models/audio_reciter_model.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_download_notification_manager.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_status.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/services/base_quran_download_notification_service.dart';

class FakeNotificationService implements BaseQuranDownloadNotificationService {
  final List<Map<String, dynamic>> progressCalls = [];
  final List<Map<String, dynamic>> terminalCalls = [];
  final List<int> dismissCalls = [];
  bool dismissAllCalled = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required double? progressRatio,
    required bool isOngoing,
    required bool isIndeterminate,
  }) async {
    progressCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'progressRatio': progressRatio,
      'isOngoing': isOngoing,
      'isIndeterminate': isIndeterminate,
    });
  }

  @override
  Future<void> showTerminalNotification({
    required int id,
    required String title,
    required String body,
    required bool isError,
  }) async {
    terminalCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'isError': isError,
    });
  }

  @override
  Future<void> dismissNotification(int id) async {
    dismissCalls.add(id);
  }

  @override
  Future<void> dismissSingleSurahNotification() async {
    dismissCalls.add(BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId);
  }

  @override
  Future<void> dismissQueueNotification() async {
    dismissCalls.add(BaseQuranDownloadNotificationService.kFullQuranDownloadNotificationId);
  }

  @override
  Future<void> dismissAllQuranDownloadNotifications() async {
    dismissAllCalled = true;
    dismissCalls.add(BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId);
    dismissCalls.add(BaseQuranDownloadNotificationService.kFullQuranDownloadNotificationId);
  }
}

class FakeLocalDataSource implements BaseQuranAudioLocalDataSource {
  @override
  Future<List<AudioReciterModel>?> getCachedReciters() async => [
        AudioReciterModel(
          id: '7',
          name: 'Mishari Rashid al-`Afasy',
          arabicName: 'مشاري راشد العفاسي',
        ),
      ];

  @override
  Future<AudioDownloadModel?> getDownloadRecord(int surahNumber, String reciterId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationService fakeNotifService;
  late FakeLocalDataSource fakeLocalDataSource;
  late QuranDownloadNotificationManager manager;

  setUp(() {
    fakeNotifService = FakeNotificationService();
    fakeLocalDataSource = FakeLocalDataSource();
    manager = QuranDownloadNotificationManager(
      notificationService: fakeNotifService,
      localDataSource: fakeLocalDataSource,
      throttleWindow: const Duration(milliseconds: 100), // Short window for testing
    );
  });

  tearDown(() {
    manager.dispose();
  });

  group('QuranDownloadNotificationManager Tests', () {
    test('Single-Surah Download: tracks lifecycle and formats Arabic notifications', () async {
      final controller = StreamController<DownloadProgress>.broadcast();

      manager.trackSingleSurahDownload(
        surahNumber: 1, // Al-Fatihah
        reciterId: '7',
        reciterName: 'مشاري راشد العفاسي',
        progressStream: controller.stream,
      );

      // 1. Initial starting notification
      expect(fakeNotifService.progressCalls.length, equals(1));
      expect(fakeNotifService.progressCalls.first['title'], equals('سورة الفاتحة — مشاري راشد العفاسي'));
      expect(fakeNotifService.progressCalls.first['body'], equals('بدء تحميل السورة...'));

      // 2. Downloading update
      controller.add(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 500000,
        expectedTotalBytes: 1000000,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(fakeNotifService.progressCalls.length, equals(2));
      expect(fakeNotifService.progressCalls.last['body'], contains('50%'));

      // 3. Verifying update (immediate)
      controller.add(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.verifying,
        downloadedBytes: 1000000,
        expectedTotalBytes: 1000000,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeNotifService.progressCalls.last['body'], equals('جاري التحقق من سلامة الملف الصوتي...'));
      expect(fakeNotifService.progressCalls.last['isIndeterminate'], isTrue);

      // 4. Completed terminal update
      controller.add(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.completed,
        downloadedBytes: 1000000,
        expectedTotalBytes: 1000000,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeNotifService.terminalCalls.length, equals(1));
      expect(fakeNotifService.terminalCalls.first['title'], equals('اكتمل التحميل'));
      expect(fakeNotifService.terminalCalls.first['body'], contains('تم تحميل سورة الفاتحة'));
      expect(fakeNotifService.terminalCalls.first['isError'], isFalse);

      await controller.close();
    });

    test('Throttling (C3): Coalesces rapid updates and flushes trailing update', () async {
      final controller = StreamController<DownloadProgress>.broadcast();

      manager.trackSingleSurahDownload(
        surahNumber: 2, // Al-Baqarah
        reciterId: '7',
        reciterName: 'مشاري راشد العفاسي',
        progressStream: controller.stream,
      );

      // Starting call was dispatched
      expect(fakeNotifService.progressCalls.length, equals(1));

      // Emit 10 rapid progress updates within 40ms (window is 100ms)
      for (int i = 1; i <= 10; i++) {
        controller.add(DownloadProgress(
          surahNumber: 2,
          reciterId: '7',
          status: AudioDownloadStatus.downloading,
          downloadedBytes: i * 100000,
          expectedTotalBytes: 1000000,
        ));
      }

      // Within the 100ms throttle window from the initial 'starting' call,
      // all 10 updates are coalesced and buffered; none fire immediately.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeNotifService.progressCalls.length, equals(1));

      // Wait for throttle window (100ms) to expire so trailing flush fires
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // Trailing flush dispatched the latest coalesced update (100%)
      expect(fakeNotifService.progressCalls.length, equals(2));
      expect(fakeNotifService.progressCalls.last['body'], contains('100%'));

      await controller.close();
    });

    test('Session Guard (C4): Discards stale events from prior operations', () async {
      final oldController = StreamController<DownloadProgress>.broadcast();
      final newController = StreamController<DownloadProgress>.broadcast();

      // Start operation 1 (Surah 1)
      manager.trackSingleSurahDownload(
        surahNumber: 1,
        reciterId: '7',
        reciterName: 'مشاري راشد العفاسي',
        progressStream: oldController.stream,
      );

      // Start operation 2 (Surah 2) which supersedes operation 1
      manager.trackSingleSurahDownload(
        surahNumber: 2,
        reciterId: '7',
        reciterName: 'مشاري راشد العفاسي',
        progressStream: newController.stream,
      );

      final callCountAfterOp2 = fakeNotifService.progressCalls.length;

      // Emit event on oldController (Surah 1)
      oldController.add(DownloadProgress(
        surahNumber: 1,
        reciterId: '7',
        status: AudioDownloadStatus.downloading,
        downloadedBytes: 800000,
        expectedTotalBytes: 1000000,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Stale event MUST BE dropped: call count unchanged
      expect(fakeNotifService.progressCalls.length, equals(callCountAfterOp2));

      await oldController.close();
      await newController.close();
    });

    test('Full-Quran Queue Progress: formats determinate and indeterminate states', () async {
      // 1. Determinate queue progress
      await manager.handleQueueProgress(const QuranDownloadQueueProgress(
        queueId: 'queue_1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: 10,
        activeSurahNumber: 11,
        aggregateRatio: 0.15,
        downloadedBytes: 15000000,
        totalExpectedBytes: 100000000,
      ));

      expect(fakeNotifService.progressCalls.isNotEmpty, isTrue);
      final lastCall = fakeNotifService.progressCalls.last;
      expect(lastCall['title'], contains('تحميل المصحف كاملاً'));
      expect(lastCall['body'], contains('10 من 114 سورة (15%)'));
      expect(lastCall['body'], contains('سورة هود')); // Surah 11 is Hud
      expect(lastCall['isIndeterminate'], isFalse);

      // 2. Indeterminate queue progress (totalExpectedBytes is null)
      await manager.handleQueueProgress(const QuranDownloadQueueProgress(
        queueId: 'queue_1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.running,
        totalItems: 114,
        completedItems: 20,
        activeSurahNumber: 21,
        aggregateRatio: 0.0,
        downloadedBytes: 30000000,
        totalExpectedBytes: null,
      ));

      // Wait a moment for window or flush
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final indetCall = fakeNotifService.progressCalls.last;
      expect(indetCall['body'], contains('20 من 114 سورة • سورة الأنبياء')); // Surah 21 is Al-Anbiya
      expect(indetCall['isIndeterminate'], isTrue);

      // 3. Paused queue progress
      await manager.handleQueueProgress(const QuranDownloadQueueProgress(
        queueId: 'queue_1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.paused,
        totalItems: 114,
        completedItems: 20,
        aggregateRatio: 0.20,
        downloadedBytes: 30000000,
        totalExpectedBytes: 100000000,
      ));

      final pausedCall = fakeNotifService.progressCalls.last;
      expect(pausedCall['title'], contains('متوقف مؤقتاً'));
      expect(pausedCall['isOngoing'], isFalse); // Ongoing is false on pause

      // 4. Completed queue progress
      await manager.handleQueueProgress(const QuranDownloadQueueProgress(
        queueId: 'queue_1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.completed,
        totalItems: 114,
        completedItems: 114,
        aggregateRatio: 1.0,
        downloadedBytes: 100000000,
        totalExpectedBytes: 100000000,
      ));

      expect(fakeNotifService.terminalCalls.isNotEmpty, isTrue);
      final termCall = fakeNotifService.terminalCalls.last;
      expect(termCall['title'], equals('اكتمل تحميل المصحف كاملاً'));
      expect(termCall['body'], contains('114 سورة'));
      expect(termCall['isError'], isFalse);

      // 5. Cancelled queue progress dismisses notification
      await manager.handleQueueProgress(const QuranDownloadQueueProgress(
        queueId: 'queue_1',
        reciterId: '7',
        status: QuranDownloadQueueStatus.cancelled,
        totalItems: 114,
      ));

      expect(fakeNotifService.dismissCalls, contains(BaseQuranDownloadNotificationService.kFullQuranDownloadNotificationId));
    });

    test('formatUserFriendlyAudioError correctly handles network, storage, 404, and integrity errors', () {
      expect(
        formatUserFriendlyAudioError('SocketException: OS Error: Connection refused, errno = 111'),
        equals('تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.'),
      );
      expect(
        formatUserFriendlyAudioError('ClientException with SocketException: Failed host lookup'),
        equals('تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.'),
      );
      expect(
        formatUserFriendlyAudioError('FileSystemException: No space left on device'),
        equals('المساحة التخزينية على جهازك غير كافية لإتمام التحميل.'),
      );
      expect(
        formatUserFriendlyAudioError('HttpException: 404 Not Found'),
        equals('الملف الصوتي غير متوفر على الخادم لهذا القارئ.'),
      );
      expect(
        formatUserFriendlyAudioError('HttpException: Stream truncated: received 10 bytes, expected 100'),
        equals('فشل التحقق من اكتمال الملف الصوتي. يرجى إعادة المحاولة.'),
      );
      expect(
        formatUserFriendlyAudioError('فشل في حفظ الملف الصوتي'),
        equals('فشل في حفظ الملف الصوتي'),
      );
    });
  });
}
