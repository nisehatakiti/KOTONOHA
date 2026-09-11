import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/utils/distance_utils.dart';

void main() {
  group('classifyDistanceState', () {
    test('11m is approaching', () {
      expect(classifyDistanceState(11), KotonohaDistanceState.approaching);
    });

    test('10m is touchable', () {
      expect(classifyDistanceState(10), KotonohaDistanceState.touchable);
    });

    test('7m is touchable', () {
      expect(classifyDistanceState(7), KotonohaDistanceState.touchable);
    });

    test('5m is connectable', () {
      expect(classifyDistanceState(5), KotonohaDistanceState.connectable);
    });

    test('1m is connectable', () {
      expect(classifyDistanceState(1), KotonohaDistanceState.connectable);
    });
  });

  group('calculateDistanceMeters', () {
    test('is zero for the same point', () {
      final meters = calculateDistanceMeters(
        startLatitude: 35.0,
        startLongitude: 139.0,
        endLatitude: 35.0,
        endLongitude: 139.0,
      );
      expect(meters, closeTo(0, 0.001));
    });

    test('is roughly correct for a small known offset (~4m)', () {
      final meters = calculateDistanceMeters(
        startLatitude: 35.0,
        startLongitude: 139.0,
        endLatitude: 35.0000400,
        endLongitude: 139.0,
      );
      expect(meters, closeTo(4.45, 1));
    });
  });

  group('formatDistanceMeters', () {
    test('rounds to whole meters with no decimals', () {
      expect(formatDistanceMeters(3.4), 'あと 3m');
      expect(formatDistanceMeters(3.6), 'あと 4m');
      expect(formatDistanceMeters(120), 'あと 120m');
    });
  });
}
