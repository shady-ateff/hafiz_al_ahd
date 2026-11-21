import 'dart:ui';
import '../errors/quran_audio_failures.dart';

/// Atomic reservation ticket issued by [BaseQuranAudioDownloadCoordinator].
///
/// Guaranteed properties:
/// 1. Exactly one active ticket exists across the entire application runtime.
/// 2. Disposing the ticket atomically releases the coordinator lock.
class DownloadReservationTicket {
  /// Human-readable diagnostic description of the reserved operation.
  final String description;

  final VoidCallback _onDispose;
  bool _isDisposed = false;

  DownloadReservationTicket({
    required this.description,
    required VoidCallback onDispose,
  }) : _onDispose = onDispose;

  /// Whether this ticket has already been released.
  bool get isDisposed => _isDisposed;

  /// Releases the reservation ticket atomically.
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _onDispose();
    }
  }
}

/// Domain contract for coordinating mutual exclusion across Quran Audio download operations.
///
/// Strictly enforces that:
/// - No single-Surah download can begin while a full-Quran queue is active.
/// - No full-Quran queue can begin while a single-Surah download is active.
abstract class BaseQuranAudioDownloadCoordinator {
  /// Whether any download operation (single Surah or full-Quran queue) is actively reserved.
  bool get isBusy;

  /// Human-readable description of current active reservation, or null if idle.
  String? get activeReservationDescription;

  /// Atomically requests permission to start a single Surah download.
  ///
  /// Throws [QuranAudioConflictFailure] if any other download operation is currently active.
  Future<DownloadReservationTicket> reserveSingleSurah({
    required int surahNumber,
    required String reciterId,
  });

  /// Atomically requests permission to start or resume a full-Quran download queue.
  ///
  /// Throws [QuranAudioConflictFailure] if any other download operation is currently active.
  Future<DownloadReservationTicket> reserveQueue({
    required String queueId,
    required String reciterId,
  });
}
