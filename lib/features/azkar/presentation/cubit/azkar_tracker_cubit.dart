import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';

class AzkarTrackerState {
  final Map<String, int> counts;
  final DateTime lastUpdated;

  AzkarTrackerState({required this.counts, required this.lastUpdated});

  factory AzkarTrackerState.initial() {
    return AzkarTrackerState(
      counts: {},
      lastUpdated: DateTime.now(),
    );
  }

  AzkarTrackerState copyWith({
    Map<String, int>? counts,
    DateTime? lastUpdated,
  }) {
    return AzkarTrackerState(
      counts: counts ?? this.counts,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class AzkarTrackerCubit extends Cubit<AzkarTrackerState> {
  AzkarTrackerCubit() : super(AzkarTrackerState.initial());

  void checkAndResetDay() {
    final now = DateTime.now();
    if (state.lastUpdated.day != now.day ||
        state.lastUpdated.month != now.month ||
        state.lastUpdated.year != now.year) {
      emit(AzkarTrackerState.initial());
    }
  }

  void incrementZikr(AzkarItem item) {
    checkAndResetDay();
    final currentCount = state.counts[item.text] ?? 0;
    if (currentCount < item.count) {
      final newCounts = Map<String, int>.from(state.counts);
      newCounts[item.text] = currentCount + 1;
      emit(state.copyWith(counts: newCounts, lastUpdated: DateTime.now()));
    }
  }

  void resetZikr(String text) {
    checkAndResetDay();
    if (state.counts.containsKey(text)) {
      final newCounts = Map<String, int>.from(state.counts);
      newCounts[text] = 0;
      emit(state.copyWith(counts: newCounts, lastUpdated: DateTime.now()));
    }
  }

  void resetCategory(List<AzkarItem> items) {
    final newCounts = Map<String, int>.from(state.counts);
    for (var item in items) {
      newCounts[item.text] = 0;
    }
    emit(state.copyWith(counts: newCounts)); 
  }

  int getZikrCount(String text) {
    // If day changed, return 0 for UI, but don't emit here to avoid build errors
    final now = DateTime.now();
    if (state.lastUpdated.day != now.day ||
        state.lastUpdated.month != now.month ||
        state.lastUpdated.year != now.year) {
      return 0;
    }
    return state.counts[text] ?? 0;
  }
}

