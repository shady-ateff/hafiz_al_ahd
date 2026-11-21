import '../../domain/entities/ayah_timing.dart';

/// Highly optimized, binary-search based Ayah tracking engine.
///
/// Converts continuous audio playback positions into accurate Ayah highlight intervals
/// with deterministic overlap resolution and natural pause/gap dampening.
class AyahTrackingEngine {
  /// Default grace period (in milliseconds) to retain the last Ayah highlight
  /// during natural recitation pauses between Ayahs.
  static const int kDefaultGapGracePeriodMs = 1500;

  final int gapGracePeriodMs;

  List<AyahTiming> _timings = const [];
  int _lastResolvedIndex = -1;
  int _lastPositionMs = 0;

  AyahTrackingEngine({this.gapGracePeriodMs = kDefaultGapGracePeriodMs});

  /// Loads and prepares a validated, sorted list of [AyahTiming] intervals.
  void setTimings(List<AyahTiming> sortedTimings) {
    _timings = sortedTimings;
    reset();
  }

  /// Resets the progression guards (e.g. on Surah change or playback stop).
  void reset() {
    _lastResolvedIndex = -1;
    _lastPositionMs = 0;
  }

  /// Resolves the currently active [AyahTiming] for a given [positionMs].
  ///
  /// - Uses binary search: $O(\log n)$ per lookup.
  /// - Enforces monotonic forward progression to prevent flickering on overlapping intervals.
  /// - Honors explicit backward seeking by recalculating from the new position.
  AyahTiming? resolveAyahAtPosition(
    int positionMs, {
    bool isExplicitSeek = false,
  }) {
    if (_timings.isEmpty || positionMs < 0) {
      return null;
    }

    // 1. Detect explicit backward seek: position moved backward by > 500ms
    final isBackwardMovement = positionMs < (_lastPositionMs - 500);
    if (isExplicitSeek || isBackwardMovement) {
      _lastResolvedIndex = -1;
    }
    _lastPositionMs = positionMs;

    // 2. Binary search for the latest Ayah whose timestampFrom <= positionMs
    int low = 0;
    int high = _timings.length - 1;
    int candidateIndex = -1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_timings[mid].timestampFrom <= positionMs) {
        candidateIndex = mid;
        low = mid + 1; // Look for a later starting candidate
      } else {
        high = mid - 1;
      }
    }

    if (candidateIndex == -1) {
      // Position is before the first Ayah starts (e.g. initial silence / intro)
      return null;
    }

    final candidate = _timings[candidateIndex];

    // 3. Check if position falls inside candidate's interval
    if (positionMs <= candidate.timestampTo) {
      // Monotonic Progression Guard for normal playback
      if (_lastResolvedIndex != -1 && candidateIndex < _lastResolvedIndex && !isExplicitSeek) {
        return _timings[_lastResolvedIndex];
      }
      _lastResolvedIndex = candidateIndex;
      return candidate;
    }

    // 4. Position is past candidate.timestampTo -> Check for Gap vs Overlap
    // Check if the next Ayah has already started (overlap case)
    if (candidateIndex + 1 < _timings.length) {
      final next = _timings[candidateIndex + 1];
      if (positionMs >= next.timestampFrom && positionMs <= next.timestampTo) {
        _lastResolvedIndex = candidateIndex + 1;
        return next;
      }
    }

    // 5. Gap handling: position is in a gap between candidate and next
    final timeSinceCandidateEnd = positionMs - candidate.timestampTo;
    if (timeSinceCandidateEnd <= gapGracePeriodMs) {
      // Retain previous highlight during short recitation pause
      return candidate;
    }

    // Gap exceeded grace period -> clear highlight
    return null;
  }
}
