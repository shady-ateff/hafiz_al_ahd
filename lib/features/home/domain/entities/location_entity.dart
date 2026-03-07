class LocationEntity {
  final double latitude;
  final double longitude;
  final String city;
  final String? country;

  LocationEntity({
    required this.latitude,
    required this.longitude,
    required this.city,
    this.country,
  });
}