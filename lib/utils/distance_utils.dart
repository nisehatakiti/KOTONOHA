import 'dart:math';

/// KOTONOHA's three distance states for a single 言の葉 (STEP10-B), kept
/// as an enum rather than scattering `if (meters <= 5)` checks through the
/// UI — this is a distinct responsibility from LocationService (which only
/// gets *a* position, not distances between two positions).
enum KotonohaDistanceState {
  /// More than 10m away.
  approaching,

  /// 5m〜10m: content is visible (docs/requirements.md 10m), but not close
  /// enough to connect yet.
  touchable,

  /// 5m以内: close enough to connect (the actual connect API isn't
  /// implemented until a later STEP — this state only controls whether
  /// the "繋ぐ" button is enabled).
  connectable,
}

const double kConnectableRadiusMeters = 5.0;
const double kTouchableRadiusMeters = 10.0;

/// 「発見できる距離」(STEP12): the map only ever fetches/shows Root pins
/// within this radius of the user's current location — distinct from
/// [kConnectableRadiusMeters], which gates a Root's *content* once its pin
/// is already visible. See lib/utils/location_bounds_utils.dart for where
/// this is applied (Bounding Box query + the Haversine final filter).
const double kMarkerVisibleRadiusMeters = 3000.0;

KotonohaDistanceState classifyDistanceState(double meters) {
  if (meters <= kConnectableRadiusMeters) return KotonohaDistanceState.connectable;
  if (meters <= kTouchableRadiusMeters) return KotonohaDistanceState.touchable;
  return KotonohaDistanceState.approaching;
}

String describeDistanceState(KotonohaDistanceState state) {
  switch (state) {
    case KotonohaDistanceState.approaching:
      return '近づく';
    case KotonohaDistanceState.touchable:
      return '触れられる距離';
    case KotonohaDistanceState.connectable:
      return '繋げる距離';
  }
}

/// "あと ○m" — whole meters only, no decimals (STEP10-B spec).
String formatDistanceMeters(double meters) => 'あと ${meters.round()}m';

/// Great-circle distance between two coordinates, in meters (Haversine
/// formula) — the same method used server-side for pin clustering
/// (KOTONOHA-API KotonohaRepository::haversineMeters), kept here as a
/// small pure function rather than folded into LocationService.
double calculateDistanceMeters({
  required double startLatitude,
  required double startLongitude,
  required double endLatitude,
  required double endLongitude,
}) {
  const earthRadiusMeters = 6371000.0;

  final lat1 = startLatitude * pi / 180;
  final lat2 = endLatitude * pi / 180;
  final deltaLat = (endLatitude - startLatitude) * pi / 180;
  final deltaLng = (endLongitude - startLongitude) * pi / 180;

  final a =
      sin(deltaLat / 2) * sin(deltaLat / 2) +
      cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadiusMeters * c;
}
