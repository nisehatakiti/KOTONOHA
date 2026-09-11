/// Minimal representation of a "言の葉" pin as shown on the map.
///
/// Only the fields needed for pin placement are modeled here
/// (see docs/api.md `GET /api/kotonoha/nearby`); photo/comment content
/// is fetched separately once the 10m detail view is implemented.
class KotonohaPin {
  const KotonohaPin({
    required this.id,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final double latitude;
  final double longitude;
}
