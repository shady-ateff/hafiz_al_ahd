import '../../domain/entities/location_entity.dart';

class LocationModel extends LocationEntity {
  LocationModel({
    required super.latitude,
    required super.longitude,
    required super.city,
    super.country,
  });

  // تحويل من JSON (جاي من الكاش) لـ Object
  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      latitude: json['lat'],
      longitude: json['lng'],
      city: json['city'],
      country: json['country'],
    );
  }

  // تحويل من Object لـ JSON (عشان نحفظه في الكاش)
  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lng': longitude,
      'city': city,
      'country': country,
    };
  }
}