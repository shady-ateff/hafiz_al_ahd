import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/usecases/get_quran_tafseer_use_case.dart';
import 'quran_tafseer_state.dart';

/// Cubit managing presentation state for Quran Tafseer commentary.
///
/// Guarantees:
/// 1. Latest-request-wins concurrency semantics via monotonic sequence ID.
/// 2. Closure safety preventing post-close emissions.
/// 3. Clear unidirectional state flow: Initial -> Loading -> Loaded / Error.
class QuranTafseerCubit extends Cubit<QuranTafseerState> {
  final GetQuranTafseerUseCase getQuranTafseerUseCase;

  int _currentRequestId = 0;

  QuranTafseerCubit({required this.getQuranTafseerUseCase})
    : super(const QuranTafseerInitial());

  /// Requests the Tafseer commentary for [ayahId].
  ///
  /// Emits [QuranTafseerLoading] immediately. When the request resolves,
  /// emits [QuranTafseerLoaded] on success or [QuranTafseerError] on failure.
  ///
  /// Older in-flight requests that resolve after a newer request has started
  /// are automatically dropped and will never overwrite the active state.
  Future<void> loadTafseer(AyahId ayahId) async {
    final requestId = ++_currentRequestId;

    emit(QuranTafseerLoading(ayahId));

    try {
      final result = await getQuranTafseerUseCase(ayahId);

      // Guard 1: Safety against emissions after Cubit closure
      if (isClosed) return;

      // Guard 2: Stale response protection (Latest-request-wins)
      if (requestId != _currentRequestId) return;

      result.fold(
        (failure) =>
            emit(QuranTafseerError(ayahId: ayahId, message: failure.message)),
        (tafseer) => emit(QuranTafseerLoaded(tafseer)),
      );
    } catch (e) {
      if (isClosed || requestId != _currentRequestId) return;
      emit(
        QuranTafseerError(
          ayahId: ayahId,
          message: 'Failed to load Tafseer: $e',
        ),
      );
    }
  }

  /// Resets state back to [QuranTafseerInitial] and invalidates any in-flight requests.
  void reset() {
    _currentRequestId++;
    if (!isClosed) {
      emit(const QuranTafseerInitial());
    }
  }
}
