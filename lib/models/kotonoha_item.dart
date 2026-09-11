/// A single 言の葉 as shown in the tap-a-pin tile list (STEP10-A), fetched
/// from `GET /api/kotonoha/{id}`. Unlike [KotonohaPin] (map markers only),
/// this carries the photo/comment/accuracy needed for the tile UI.
class KotonohaItem {
  const KotonohaItem({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.imageUrl,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String? imageUrl;
  final String comment;

  /// ISO 8601 string as returned by the API (JST offset), kept as-is —
  /// only formatted for display where shown.
  final String createdAt;
}
