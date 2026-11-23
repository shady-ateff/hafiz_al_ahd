import '../entities/ward_completion_event.dart';

/// Abstract contract for reporting and observing Adhkar completion events.
///
/// Focus Mode consumes this port without depending on any Adhkar Cubit or Widget.
/// Any feature in the app can dispatch events through this port when adhkar are read.
abstract class AdhkarCompletionPort {
  /// Stream of all Adhkar completion/progress events.
  Stream<AdhkarCompletionEvent> get onAdhkarEvent;

  /// Dispatches an adhkar progress or completion event.
  void dispatchEvent(AdhkarCompletionEvent event);

  /// Disposes any underlying controllers/streams.
  void dispose();
}
