import 'dart:async';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_storage_lock.dart';

/// In-memory FIFO asynchronous mutex guaranteeing exclusive serialized execution
/// between prayer audio configurations and physical storage deletion operations.
///
/// Strictly non-reentrant: Re-entrant lock acquisition is prohibited to prevent
/// detached asynchronous tasks from inheriting direct entry privileges or leaking
/// beyond their intended critical section lifetime.
class AudioStorageLock implements BaseAudioStorageLock {
  Future<void>? _lastOperation;

  @override
  bool get isLocked => _lastOperation != null;

  @override
  Future<T> synchronized<T>(Future<T> Function() action) {
    final prev = _lastOperation;
    final completer = Completer<void>();
    _lastOperation = completer.future;

    return Future.sync(() async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      return await action();
    }).whenComplete(() {
      completer.complete();
      if (identical(_lastOperation, completer.future)) {
        _lastOperation = null;
      }
    });
  }
}
