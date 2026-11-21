import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran_audio/data/services/quran_audio_download_coordinator.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/errors/quran_audio_failures.dart';

void main() {
  late QuranAudioDownloadCoordinator coordinator;

  setUp(() {
    coordinator = QuranAudioDownloadCoordinator();
  });

  group('QA.6 Phase 6.4 - QuranAudioDownloadCoordinator Tests', () {
    test('initial state is idle and not busy', () {
      expect(coordinator.isBusy, isFalse);
      expect(coordinator.activeReservationDescription, isNull);
    });

    test('reserveSingleSurah issues ticket and blocks subsequent reservations', () async {
      final ticket1 = await coordinator.reserveSingleSurah(
        surahNumber: 1,
        reciterId: '7',
      );

      expect(coordinator.isBusy, isTrue);
      expect(coordinator.activeReservationDescription, contains('Single-Surah(surah: 1, reciter: 7)'));

      // Attempting to reserve another single Surah throws conflict
      await expectLater(
        coordinator.reserveSingleSurah(surahNumber: 2, reciterId: '7'),
        throwsA(isA<QuranAudioConflictFailure>()),
      );

      // Attempting to reserve full-Quran queue throws conflict
      await expectLater(
        coordinator.reserveQueue(queueId: 'q1', reciterId: '7'),
        throwsA(isA<QuranAudioConflictFailure>()),
      );

      // Dispose ticket
      ticket1.dispose();
      expect(coordinator.isBusy, isFalse);
      expect(coordinator.activeReservationDescription, isNull);

      // Now reservation succeeds
      final ticket2 = await coordinator.reserveQueue(queueId: 'q1', reciterId: '7');
      expect(coordinator.isBusy, isTrue);
      expect(coordinator.activeReservationDescription, contains('Full-Quran-Queue(id: q1, reciter: 7)'));

      ticket2.dispose();
      expect(coordinator.isBusy, isFalse);
    });

    test('reserveQueue blocks single Surah downloads until disposed', () async {
      final queueTicket = await coordinator.reserveQueue(
        queueId: 'q_lib_7',
        reciterId: '7',
      );

      expect(coordinator.isBusy, isTrue);

      await expectLater(
        coordinator.reserveSingleSurah(surahNumber: 112, reciterId: '7'),
        throwsA(isA<QuranAudioConflictFailure>()),
      );

      queueTicket.dispose();
      expect(coordinator.isBusy, isFalse);

      final surahTicket = await coordinator.reserveSingleSurah(
        surahNumber: 112,
        reciterId: '7',
      );
      expect(coordinator.isBusy, isTrue);
      surahTicket.dispose();
    });

    test('ticket disposal is idempotent', () async {
      final ticket = await coordinator.reserveSingleSurah(
        surahNumber: 1,
        reciterId: '7',
      );

      expect(ticket.isDisposed, isFalse);
      ticket.dispose();
      expect(ticket.isDisposed, isTrue);
      expect(coordinator.isBusy, isFalse);

      // Second dispose is safe
      ticket.dispose();
      expect(coordinator.isBusy, isFalse);
    });
  });
}
