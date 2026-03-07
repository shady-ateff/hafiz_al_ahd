import 'dart:convert';
import 'package:hafiz_al_ahd/core/errors/exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_model.dart';

abstract class BaseLocationLocalDataSource {
  Future<void> cacheLocation(LocationModel locationToCache);
  Future<LocationModel> getCachedLocation();
}

const String cachedLocationKey = 'CACHED_LOCATION';

class LocationLocalDataSourceImpl implements BaseLocationLocalDataSource {
  final SharedPreferences sharedPreferences;

  LocationLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheLocation(LocationModel locationToCache) async {
    // بنحول الموديل لـ JSON String ونحفظه
    final jsonString = json.encode(locationToCache.toJson());
    await sharedPreferences.setString(cachedLocationKey, jsonString);
  }

  @override
  Future<LocationModel> getCachedLocation() async {
    final jsonString = sharedPreferences.getString(cachedLocationKey);

    if (jsonString != null) {
      // لو لقينا داتا، نرجعها كموديل
      return LocationModel.fromJson(json.decode(jsonString));
    } else {
      // لو الكاش فاضي، نرمي Exception (والمدير هيتصرف فيه)
      throw CacheException();
    }
  }
}
