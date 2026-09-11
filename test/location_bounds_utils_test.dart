import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/utils/distance_utils.dart';
import 'package:kotonoha/utils/location_bounds_utils.dart';

const _centerLat = 35.681236;
const _centerLng = 139.767125;

double _distanceFrom(double lat, double lng) => calculateDistanceMeters(
  startLatitude: _centerLat,
  startLongitude: _centerLng,
  endLatitude: lat,
  endLongitude: lng,
);

/// A point due north of the center whose Haversine distance back to the
/// center is as close to [meters] as double-precision round-tripping
/// allows — good enough for the "clearly inside/outside" cases (STEP12
/// 14-2), but not for testing the exact `<=` boundary (see below).
double _latitudeNorthOfCenter(double meters) {
  const earthRadiusMeters = 6371000.0;
  final deltaLatDegrees = (meters / earthRadiusMeters) * 180 / 3.14159265358979323846;
  return _centerLat + deltaLatDegrees;
}

void main() {
  group('computeBoundingBox (STEP12 14-1)', () {
    test('the box fully contains the requested radius', () {
      final box = computeBoundingBox(
        latitude: _centerLat,
        longitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      expect(box.north, greaterThan(_centerLat));
      expect(box.south, lessThan(_centerLat));
      expect(box.east, greaterThan(_centerLng));
      expect(box.west, lessThan(_centerLng));

      // Each edge, walked straight out from the center, should land
      // within a few meters of the requested radius.
      expect(_distanceFrom(box.north, _centerLng), closeTo(3000, 5));
      expect(_distanceFrom(box.south, _centerLng), closeTo(3000, 5));
      expect(_distanceFrom(_centerLat, box.east), closeTo(3000, 5));
      expect(_distanceFrom(_centerLat, box.west), closeTo(3000, 5));
    });

    test('the box corners lie outside the 3km circle (Bounding Box '
        'over-covers, as expected)', () {
      final box = computeBoundingBox(
        latitude: _centerLat,
        longitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      final cornerDistance = _distanceFrom(box.north, box.east);
      expect(cornerDistance, greaterThan(kMarkerVisibleRadiusMeters));
    });

    test('the longitude span narrows toward the equator and widens at '
        'higher latitudes (cos(latitude) term)', () {
      final atEquator = computeBoundingBox(
        latitude: 0,
        longitude: 0,
        radiusMeters: 3000,
      );
      final atHighLatitude = computeBoundingBox(
        latitude: 60,
        longitude: 0,
        radiusMeters: 3000,
      );

      final equatorSpan = atEquator.east - atEquator.west;
      final highLatitudeSpan = atHighLatitude.east - atHighLatitude.west;
      expect(highLatitudeSpan, greaterThan(equatorSpan));
    });

    test('never divides by zero near the poles', () {
      expect(
        () => computeBoundingBox(latitude: 89.9, longitude: 0, radiusMeters: 3000),
        returnsNormally,
      );
    });
  });

  group('filterPinsWithinRadius (STEP12 14-2)', () {
    test('2999m: kept', () {
      final pin = KotonohaPin(
        id: '1',
        latitude: _latitudeNorthOfCenter(2999),
        longitude: _centerLng,
      );

      final result = filterPinsWithinRadius(
        pins: [pin],
        centerLatitude: _centerLat,
        centerLongitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      expect(result, hasLength(1));
    });

    test('3001m: dropped', () {
      final pin = KotonohaPin(
        id: '1',
        latitude: _latitudeNorthOfCenter(3001),
        longitude: _centerLng,
      );

      final result = filterPinsWithinRadius(
        pins: [pin],
        centerLatitude: _centerLat,
        centerLongitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      expect(result, isEmpty);
    });

    test('a pin at exactly radiusMeters away is kept (inclusive '
        'boundary)', () {
      // Constructed so the measured distance and the filter's radius are
      // literally the same computed double — this exercises the `<=`
      // boundary itself without risking a false failure from independent
      // floating-point round-trip error between two separately-derived
      // "3000m" values.
      final pin = KotonohaPin(
        id: '1',
        latitude: _latitudeNorthOfCenter(3000),
        longitude: _centerLng,
      );
      final measuredDistance = _distanceFrom(pin.latitude, pin.longitude);

      final result = filterPinsWithinRadius(
        pins: [pin],
        centerLatitude: _centerLat,
        centerLongitude: _centerLng,
        radiusMeters: measuredDistance,
      );

      expect(result, hasLength(1));
    });

    test('keeps near pins, drops far pins, preserves order', () {
      final near = KotonohaPin(
        id: 'near',
        latitude: _latitudeNorthOfCenter(100),
        longitude: _centerLng,
      );
      final far = KotonohaPin(
        id: 'far',
        latitude: _latitudeNorthOfCenter(5000),
        longitude: _centerLng,
      );

      final result = filterPinsWithinRadius(
        pins: [near, far],
        centerLatitude: _centerLat,
        centerLongitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      expect(result.map((p) => p.id).toList(), ['near']);
    });

    test('an empty pin list stays empty', () {
      final result = filterPinsWithinRadius(
        pins: const [],
        centerLatitude: _centerLat,
        centerLongitude: _centerLng,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );

      expect(result, isEmpty);
    });
  });
}
