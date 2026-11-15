import 'dart:async';

/// Contract for coordinating exclusive access between prayer audio configuration and storage deletions.
///
/// Eliminates time-of-check to time-of-use (TOCTOU) race conditions by serializing:
/// 1. Prayer alarm configuration updates (prayer audio overrides & global audio source).
/// 2. Storage file deletion and eviction.
abstract class BaseAudioStorageLock {
  /// Executes [action] exclusively under the audio storage lock.
  Future<T> synchronized<T>(Future<T> Function() action);

  /// Whether the lock is currently held by an active operation.
  bool get isLocked;
}

