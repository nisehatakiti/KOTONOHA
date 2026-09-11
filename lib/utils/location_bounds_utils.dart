import 'dart:math';

import '../models/kotonoha_pin.dart';
import 'distance_utils.dart';

/// A lat/lng bounding box expressed as its four edges — exactly the shape
/// `GET /api/kotonoha`'s `north`/`south`/`east`/`west` query params expect
/// (KOTONOHA-API docs). Deliberately not `google_maps_flutter`'s
/// `LatLngBounds`: this is computed from a center point and a radius, not
/// read off a live map camera, so it has no reason to depend on the maps
/// plugin.
class BoundingBox {
  const BoundingBox({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;
}

const double _metersPerDegreeLatitude = 111320.0;

/// A rectangular region that fully contains the circle of [radiusMeters]
/// around ([latitude], [longitude]) (STEP12 3km表示範囲).
///
/// `GET /api/kotonoha`'s Bounding Box search has no concept of a radius, so
/// this necessarily over-covers the circle near its corners — callers must
/// apply their own distance filter afterward (see [filterPinsWithinRadius])
/// to get an exact circle.
BoundingBox computeBoundingBox({
  required double latitude,
  required double longitude,
  required double radiusMeters,
}) {
  final latitudeDelta = radiusMeters / _metersPerDegreeLatitude;

  // cos(latitude) → 0 near the poles, which would blow up longitudeDelta;
  // KOTONOHA has no realistic users there, but clamp defensively rather
  // than risk a divide-by-(near-)zero.
  final cosLatitude = cos(latitude * pi / 180).clamp(0.01, 1.0);
  final longitudeDelta = radiusMeters / (_metersPerDegreeLatitude * cosLatitude);

  return BoundingBox(
    north: latitude + latitudeDelta,
    south: latitude - latitudeDelta,
    east: longitude + longitudeDelta,
    west: longitude - longitudeDelta,
  );
}

/// The exact-circle filter that [computeBoundingBox]'s rectangle alone
/// can't provide (STEP12 section 4: 「Bounding Boxの角にある、実際には3kmを
/// 超える投稿」を防ぐ) — keeps only the [pins] whose great-circle distance
/// from ([centerLatitude], [centerLongitude]) is at most [radiusMeters],
/// via the same Haversine formula used for the 5m server-side check
/// ([calculateDistanceMeters]). Order is preserved.
List<KotonohaPin> filterPinsWithinRadius({
  required List<KotonohaPin> pins,
  required double centerLatitude,
  required double centerLongitude,
  required double radiusMeters,
}) {
  return [
    for (final pin in pins)
      if (calculateDistanceMeters(
            startLatitude: centerLatitude,
            startLongitude: centerLongitude,
            endLatitude: pin.latitude,
            endLongitude: pin.longitude,
          ) <=
          radiusMeters)
        pin,
  ];
}
