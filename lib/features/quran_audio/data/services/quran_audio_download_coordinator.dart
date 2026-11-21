import 'dart:async';
import '../../domain/errors/quran_audio_failures.dart';
import '../../domain/services/base_quran_audio_download_coordinator.dart';

/// Lightweight async mutex guaranteeing sequential execution of critical sections.
class _AsyncMutex {
  Future<void>? _last;

  Future<T> synchronized<T>(Future<T> Function() action) {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;

    return Future.sync(() async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      return await action();
    }).whenComplete(() {
      completer.complete();
    });
  }
}

/// Concrete coordinator enforcing mutual exclusion across all Quran audio download operations.
///
/// Guaranteed properties:
/// 1. Exactly one active download operation (single Surah or full Quran queue) at any instant.
/// 2. Thread-safe atomic reservation ticket issuance.
/// 3. Idempotent ticket release.
class QuranAudioDownloadCoordinator implements BaseQuranAudioDownloadCoordinator {
  final _AsyncMutex _mutex = _AsyncMutex();
  DownloadReservationTicket? _activeTicket;

  @override
  bool get isBusy => _activeTicket != null && !_activeTicket!.isDisposed;

  @override
  String? get activeReservationDescription =>
      isBusy ? _activeTicket!.description : null;

  @override
  Future<DownloadReservationTicket> reserveSingleSurah({
    required int surahNumber,
    required String reciterId,
  }) async {
    return _mutex.synchronized(() async {
      if (isBusy) {
        throw QuranAudioConflictFailure(
          message: 'تعارض في التنزيل: لا يمكن تحميل سورة $surahNumber للقارئ $reciterId '
              'لوجود عملية تنزيل أخرى قيد التنفيذ (${_activeTicket!.description})',
        );
      }

      final ticket = DownloadReservationTicket(
        description: 'Single-Surah(surah: $surahNumber, reciter: $reciterId)',
        onDispose: () {
          _mutex.synchronized(() async {
            if (_activeTicket?.description ==
                'Single-Surah(surah: $surahNumber, reciter: $reciterId)') {
              _activeTicket = null;
            }
          });
        },
      );

      _activeTicket = ticket;
      return ticket;
    });
  }

  @override
  Future<DownloadReservationTicket> reserveQueue({
    required String queueId,
    required String reciterId,
  }) async {
    return _mutex.synchronized(() async {
      if (isBusy) {
        throw QuranAudioConflictFailure(
          message: 'تعارض في التنزيل: لا يمكن بدء طابور تحميل المصحف ($queueId) '
              'لوجود عملية تنزيل أخرى قيد التنفيذ (${_activeTicket!.description})',
        );
      }

      final ticket = DownloadReservationTicket(
        description: 'Full-Quran-Queue(id: $queueId, reciter: $reciterId)',
        onDispose: () {
          _mutex.synchronized(() async {
            if (_activeTicket?.description ==
                'Full-Quran-Queue(id: $queueId, reciter: $reciterId)') {
              _activeTicket = null;
            }
          });
        },
      );

      _activeTicket = ticket;
      return ticket;
    });
  }
}
