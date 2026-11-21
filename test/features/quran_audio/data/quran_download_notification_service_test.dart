import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_download_notification_service.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/services/base_quran_download_notification_service.dart';

class FakeFlutterLocalNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  final List<Map<String, dynamic>> showCalls = [];
  final List<int> cancelCalls = [];
  bool cancelAllCalled = false;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'notificationDetails': notificationDetails,
      'payload': payload,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelCalls.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
  }

  @override
  T? resolvePlatformSpecificImplementation<T extends FlutterLocalNotificationsPlatform>() {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFlutterLocalNotificationsPlugin fakePlugin;
  late QuranDownloadNotificationService service;

  setUp(() {
    fakePlugin = FakeFlutterLocalNotificationsPlugin();
    service = QuranDownloadNotificationService(plugin: fakePlugin);
  });

  group('QuranDownloadNotificationService Unit Tests', () {
    test('showProgressNotification calls plugin.show with correct silent & progress flags', () async {
      await service.showProgressNotification(
        id: BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId,
        title: 'سورة البقرة — مشاري راشد العفاسي',
        body: 'جاري التحميل... 45%',
        progressRatio: 0.45,
        isOngoing: true,
        isIndeterminate: false,
      );

      expect(fakePlugin.showCalls.length, equals(1));
      final call = fakePlugin.showCalls.first;
      expect(call['id'], equals(BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId));
      expect(call['title'], equals('سورة البقرة — مشاري راشد العفاسي'));
      expect(call['body'], equals('جاري التحميل... 45%'));
      expect(call['payload'], equals('quran_download_9100'));

      final details = call['notificationDetails'] as NotificationDetails;
      final android = details.android;
      expect(android, isNotNull);
      expect(android!.channelId, BaseQuranDownloadNotificationService.kDownloadNotificationChannelId);
      expect(android.showProgress, isTrue);
      expect(android.maxProgress, 100);
      expect(android.progress, 45);
      expect(android.ongoing, isTrue);
      expect(android.onlyAlertOnce, isTrue);
      expect(android.playSound, isFalse);
      expect(android.enableVibration, isFalse);
    });

    test('showTerminalNotification calls plugin.show with ongoing=false and autoCancel=true', () async {
      await service.showTerminalNotification(
        id: BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId,
        title: 'اكتمل التحميل',
        body: 'تم تحميل سورة البقرة بنجاح.',
        isError: false,
      );

      expect(fakePlugin.showCalls.length, equals(1));
      final call = fakePlugin.showCalls.first;
      expect(call['id'], equals(BaseQuranDownloadNotificationService.kSingleSurahDownloadNotificationId));
      expect(call['title'], equals('اكتمل التحميل'));
      expect(call['body'], equals('تم تحميل سورة البقرة بنجاح.'));

      final details = call['notificationDetails'] as NotificationDetails;
      final android = details.android;
      expect(android, isNotNull);
      expect(android!.ongoing, isFalse);
      expect(android.autoCancel, isTrue);
      expect(android.showProgress, isFalse);
      expect(android.playSound, isFalse);
      expect(android.enableVibration, isFalse);
    });

    test('dismissNotification cancels specific ID', () async {
      await service.dismissNotification(9100);
      expect(fakePlugin.cancelCalls, contains(9100));
    });

    test('dismissSingleSurahNotification cancels 9100', () async {
      await service.dismissSingleSurahNotification();
      expect(fakePlugin.cancelCalls, contains(9100));
    });

    test('dismissQueueNotification cancels 9200', () async {
      await service.dismissQueueNotification();
      expect(fakePlugin.cancelCalls, contains(9200));
    });

    test('dismissAllQuranDownloadNotifications cancels 9100 and 9200 without calling cancelAll', () async {
      await service.dismissAllQuranDownloadNotifications();
      expect(fakePlugin.cancelCalls, contains(9100));
      expect(fakePlugin.cancelCalls, contains(9200));
      expect(fakePlugin.cancelAllCalled, isFalse);
    });
  });
}
