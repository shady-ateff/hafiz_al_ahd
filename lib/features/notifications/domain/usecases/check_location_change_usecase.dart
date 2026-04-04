import 'dart:developer';
import 'package:geolocator/geolocator.dart';
import 'package:hafiz_al_ahd/features/home/domain/usecases/get_cached_location_usecase.dart';

class CheckLocationChangeUseCase {
  final GetCachedLocationUseCase getCachedLocationUseCase;

  CheckLocationChangeUseCase({required this.getCachedLocationUseCase});

  Future<bool> execute() async {
    final cachedLocationResult = await getCachedLocationUseCase();
    bool locationChanged = false;

    await cachedLocationResult.fold((l) async => null, (cachedLocation) async {
      try {
        Position currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(accuracy: LocationAccuracy.low) ,
        );

        double distanceInMeters = Geolocator.distanceBetween(
          cachedLocation.latitude,
          cachedLocation.longitude,
          currentPosition.latitude,
          currentPosition.longitude,
        );

        if (distanceInMeters > 10000) {
          log(
            "🚨 تم اكتشاف تغيير في الموقع الجغرافي بمسافة ${distanceInMeters / 1000} كم",
          );
          locationChanged = true;
        }
      } catch (e) {
        log("Error checking location change: $e");
      }
    });

    return locationChanged;
  }
}
