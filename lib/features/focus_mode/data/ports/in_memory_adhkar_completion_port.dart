import 'dart:async';
import '../../domain/entities/ward_completion_event.dart';
import '../../domain/ports/adhkar_completion_port.dart';

/// Concrete in-memory stream-based implementation of [AdhkarCompletionPort].
class InMemoryAdhkarCompletionPort implements AdhkarCompletionPort {
  final StreamController<AdhkarCompletionEvent> _controller =
      StreamController<AdhkarCompletionEvent>.broadcast();

  @override
  Stream<AdhkarCompletionEvent> get onAdhkarEvent => _controller.stream;

  @override
  void dispatchEvent(AdhkarCompletionEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
