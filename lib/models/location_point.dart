/// A single location sample.
///
/// `accuracy` is kept alongside latitude/longitude because the backend
/// spec (docs/api.md) expects it to be sent together with the position.
class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}
