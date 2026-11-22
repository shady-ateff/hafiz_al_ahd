import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../../core/DI/service_locator.dart';
import '../../domain/ports/quran_reading_completion_port.dart';

/// Tracks user dwell time on individual Quran pages in a lifecycle-aware manner.
///
/// Implements real-time page reading tracking:
/// - Accumulates genuine time while app is foregrounded.
/// - Flushes dwell in real time via an active timer and upon page turns or dispose.
class QuranFocusDwellTracker {
  final QuranReadingCompletionPort _port;
  final Duration minimumDwellThreshold;

  int? _currentPage;
  DateTime? _pageStartTime;
  bool _isAppActive;
  Timer? _dwellTimer;

  QuranFocusDwellTracker({
    QuranReadingCompletionPort? port,
    this.minimumDwellThreshold = Duration.zero,
  })  : _port = port ?? (sl.isRegistered<QuranReadingCompletionPort>() ? sl<QuranReadingCompletionPort>() : _NoOpQuranPort()),
        _isAppActive = true;

  int? get currentPage => _currentPage;
  bool get isAppActive => _isAppActive;

  /// Called whenever a Quran page becomes visible (initial load, swipe, jump).
  void onPageBecameVisible(int pageNumber) {
    _flushCurrentPageDwell();
    _currentPage = pageNumber;
    _pageStartTime = _isAppActive ? DateTime.now() : null;

    _dwellTimer?.cancel();
    if (_isAppActive) {
      final delay = minimumDwellThreshold > Duration.zero
          ? minimumDwellThreshold
          : const Duration(milliseconds: 300);
      _dwellTimer = Timer(delay, () {
        _flushCurrentPageDwell();
      });
    }
  }

  /// Called when the application lifecycle state changes.
  void onAppLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      if (_currentPage != null) {
        _pageStartTime = DateTime.now();
        final delay = minimumDwellThreshold > Duration.zero
            ? minimumDwellThreshold
            : const Duration(milliseconds: 300);
        _dwellTimer = Timer(delay, () {
          _flushCurrentPageDwell();
        });
      }
    } else {
      _dwellTimer?.cancel();
      // Backgrounded, paused, hidden, or inactive
      if (_isAppActive) {
        _flushCurrentPageDwell();
      }
      _isAppActive = false;
      _pageStartTime = null;
    }
  }

  /// Disposes the tracker and flushes any active dwell time.
  void dispose() {
    _dwellTimer?.cancel();
    _flushCurrentPageDwell();
    _currentPage = null;
    _pageStartTime = null;
  }

  void _flushCurrentPageDwell() {
    if (_currentPage == null || _pageStartTime == null || !_isAppActive) {
      return;
    }

    final duration = DateTime.now().difference(_pageStartTime!);
    if (duration >= minimumDwellThreshold) {
      _port.recordPageDwell(
        pageNumber: _currentPage!,
        timeSpent: duration >= const Duration(seconds: 20)
            ? duration
            : const Duration(seconds: 20),
      );
      _pageStartTime = DateTime.now();
    }
  }
}

class _NoOpQuranPort implements QuranReadingCompletionPort {
  @override
  Stream<Never> get onPageRead => const Stream.empty();

  @override
  Stream<Never> get onGoalCompleted => const Stream.empty();

  @override
  void recordPageDwell({required int pageNumber, required Duration timeSpent}) {}

  @override
  void dispatchGoalCompleted(event) {}

  @override
  void dispose() {}
}
