import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A Cubit that emits the current [DateTime] every second.
///
/// Also monitors day changes (midnight transition) and notifies [onDayChanged]
/// without forcing unnecessary widget rebuilds in the UI layer.
class TimeCubit extends Cubit<DateTime> {
  Timer? _timer;
  int _lastDay;
  final void Function(DateTime newTime)? onDayChanged;

  TimeCubit({this.onDayChanged})
      : _lastDay = DateTime.now().day,
        super(DateTime.now()) {
    _startTimer();
  }

  void _startTimer() {
    // Every second, update the time and check for day change
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (now.day != _lastDay) {
        _lastDay = now.day;
        onDayChanged?.call(now);
      }
      emit(now);
    });
  }

  @override
  Future<void> close() {
    // It's important to cancel the timer when the cubit is closed
    // to prevent memory leaks.
    _timer?.cancel();
    return super.close();
  }
}
