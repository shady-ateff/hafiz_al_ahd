import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_prayer_times_use_case.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_states.dart';

class PrayerTimesCubit extends Cubit<PrayerTimesStates> {
  final GetPrayerTimesUseCase getPrayerTimesUseCase;

  PrayerTimesCubit({required this.getPrayerTimesUseCase, required PrayerTimesInitial initialState}) : super(initialState);

  Future<void> fetchPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    emit(PrayerTimesLoading());
    log('Fetching prayer times for lat: $latitude, long: $longitude, date: $date');
    try {
      final result = await getPrayerTimesUseCase(
        latitude: latitude,
        longitude: longitude,
        date: date,
        city: city,
        country: country,
      method: method,
    );

      result.fold(
        (failure) => emit(PrayerTimesError(failure.message)),
        (prayerTimes) => emit(PrayerTimesLoaded(prayerTimes)),
      );
    } catch (e) {
      emit(PrayerTimesError(e.toString()));
    }
  }
}
