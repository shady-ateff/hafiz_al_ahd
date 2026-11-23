import '../entities/ward_completion_event.dart';

/// Abstract contract for tracking and evaluating Quran reading goals.
///
/// Focus Mode consumes this port to monitor reading progress and goal completion.
abstract class QuranReadingCompletionPort {
  /// Stream of recorded page reading events.
  Stream<QuranPageReadEvent> get onPageRead;

  /// Stream of completed Quran goals.
  Stream<QuranGoalCompletedEvent> get onGoalCompleted;

  /// Registers that a user dwelled on [pageNumber] for [timeSpent].
  void recordPageDwell({
    required int pageNumber,
    required Duration timeSpent,
  });

  /// Explicitly dispatches a verified goal completion event.
  void dispatchGoalCompleted(QuranGoalCompletedEvent event);

  /// Disposes any underlying controllers/streams.
  void dispose();
}
