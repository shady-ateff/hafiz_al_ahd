import 'dart:async';
import '../../domain/entities/ward_completion_event.dart';
import '../../domain/ports/quran_reading_completion_port.dart';

/// Concrete in-memory stream-based implementation of [QuranReadingCompletionPort].
class InMemoryQuranReadingCompletionPort implements QuranReadingCompletionPort {
  final StreamController<QuranPageReadEvent> _pageController =
      StreamController<QuranPageReadEvent>.broadcast();
  final StreamController<QuranGoalCompletedEvent> _goalController =
      StreamController<QuranGoalCompletedEvent>.broadcast();

  @override
  Stream<QuranPageReadEvent> get onPageRead => _pageController.stream;

  @override
  Stream<QuranGoalCompletedEvent> get onGoalCompleted => _goalController.stream;

  @override
  void recordPageDwell({required int pageNumber, required Duration timeSpent}) {
    if (!_pageController.isClosed) {
      _pageController.add(
        QuranPageReadEvent(
          pageNumber: pageNumber,
          timeSpent: timeSpent,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  @override
  void dispatchGoalCompleted(QuranGoalCompletedEvent event) {
    if (!_goalController.isClosed) {
      _goalController.add(event);
    }
  }

  @override
  void dispose() {
    _pageController.close();
    _goalController.close();
  }
}
