import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A Cubit that emits the current [DateTime] every second.
///
/// This is used to update the UI with the current time.
class TimeCubit extends Cubit<DateTime> {
  Timer? _timer;

  TimeCubit() : super(DateTime.now()) {
    _startTimer();
  }

  void _startTimer() {
    // Every second, update the time
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      emit(DateTime.now());
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