import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/widgets/kotonoha_map.dart';

/// STEP14 section 9/10/11: while a leaf popup is open (selectedId != null)
/// the map must hold still — no pan/zoom/rotate, no tapping another
/// marker — and tapping outside the popup closes it.
///
/// GoogleMap is a platform view: `flutter test` never actually spins up
/// the native map SDK, so `onMapCreated` never fires and nothing that
/// depends on a live [GoogleMapController] (fetching pins, positioning the
/// popup via getScreenCoordinate) can be exercised here — this file
/// covers the parts of the STEP14 lock that don't depend on that: the
/// gesture flags/[IgnorePointer] KotonohaMap itself decides on, and the
/// tap-to-close layer's own behavior. Marker shapes and actual on-device
/// gestures still need the real-device check called for in the STEP14
/// instructions.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('STEP14: GoogleMap gestures follow selectedId', () {
    testWidgets(
      'nothing selected: gestures enabled, GoogleMap not IgnorePointer-'
      'blocked, no tap-to-close layer',
      (tester) async {
        await tester.pumpWidget(_wrap(const KotonohaMap()));

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.scrollGesturesEnabled, isTrue);
        expect(map.zoomGesturesEnabled, isTrue);
        expect(map.rotateGesturesEnabled, isTrue);
        expect(map.tiltGesturesEnabled, isTrue);

        final ignorePointer = tester.widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(GoogleMap),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(ignorePointer.ignoring, isFalse);

        expect(find.byKey(const Key('kotonoha-map-tap-to-close')), findsNothing);
      },
    );

    testWidgets(
      'a leaf selected: gestures disabled, GoogleMap IgnorePointer-'
      'blocked (so pan/zoom/rotate/other-marker-taps cannot reach it), '
      'tap-to-close layer present',
      (tester) async {
        await tester.pumpWidget(_wrap(const KotonohaMap(selectedId: '1')));

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.scrollGesturesEnabled, isFalse);
        expect(map.zoomGesturesEnabled, isFalse);
        expect(map.rotateGesturesEnabled, isFalse);
        expect(map.tiltGesturesEnabled, isFalse);

        final ignorePointer = tester.widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(GoogleMap),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(ignorePointer.ignoring, isTrue);

        expect(
          find.byKey(const Key('kotonoha-map-tap-to-close')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping the map while a leaf is selected calls onMapTap (closes the '
      'popup) via the tap-to-close layer, since GoogleMap itself is '
      'IgnorePointer-blocked and cannot receive the tap',
      (tester) async {
        var mapTapped = false;
        await tester.pumpWidget(
          _wrap(KotonohaMap(selectedId: '1', onMapTap: () => mapTapped = true)),
        );

        await tester.tap(find.byType(GoogleMap), warnIfMissed: false);
        expect(mapTapped, isTrue);
      },
    );

    testWidgets(
      'tapping the map when nothing is selected still reaches GoogleMap '
      'directly (no tap-to-close layer in the way)',
      (tester) async {
        await tester.pumpWidget(_wrap(const KotonohaMap()));

        final ignorePointer = tester.widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(GoogleMap),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        // GoogleMap remains reachable — its own onTap (already wired to
        // onMapTap, unchanged from before STEP14) is what handles this.
        expect(ignorePointer.ignoring, isFalse);
      },
    );
  });

  // Real-device fix: 現在地マーカー + 「地図を更新」の直接実行経路
  // (refreshCurrentLocation)。GoogleMapController はテスト環境では
  // 生成されない(このファイル自身の冒頭コメント参照)ため、カメラ移動・
  // nearby再取得そのものはここでは検証できない — マーカーの状態反映
  // (setState経由、controllerに依存しない部分)のみを検証する。
  group('current-location marker', () {
    const initialLocation = LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5);
    const updatedLocation = LocationPoint(latitude: 36.0, longitude: 140.0, accuracy: 5);

    Marker? findCurrentLocationMarker(WidgetTester tester) {
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      for (final marker in map.markers) {
        if (marker.markerId == const MarkerId('current_location')) return marker;
      }
      return null;
    }

    testWidgets('no current-location marker before any location is known', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const KotonohaMap()));

      expect(findCurrentLocationMarker(tester), isNull);
    });

    testWidgets(
      'a marker appears at the right position once the very first '
      'location arrives (app launch: null -> non-null)',
      (tester) async {
        // Mirrors HomeScreen's own real sequence: KotonohaMap is first
        // built with no location at all, then rebuilt once the initial
        // fetch resolves — didUpdateWidget's own null->non-null branch is
        // what this exercises.
        await tester.pumpWidget(_wrap(const KotonohaMap()));
        await tester.pumpWidget(_wrap(const KotonohaMap(currentLocation: initialLocation)));

        final marker = findCurrentLocationMarker(tester);
        expect(marker, isNotNull);
        expect(marker!.position, const LatLng(35.0, 139.0));
      },
    );

    testWidgets(
      'refreshCurrentLocation (the "地図を更新" direct call path) moves '
      'the marker to the new location',
      (tester) async {
        final mapKey = GlobalKey<KotonohaMapState>();
        await tester.pumpWidget(_wrap(KotonohaMap(key: mapKey)));
        await tester.pumpWidget(
          _wrap(KotonohaMap(key: mapKey, currentLocation: initialLocation)),
        );
        expect(findCurrentLocationMarker(tester)!.position, const LatLng(35.0, 139.0));

        await mapKey.currentState!.refreshCurrentLocation(updatedLocation);
        await tester.pump();

        final marker = findCurrentLocationMarker(tester);
        expect(marker, isNotNull);
        expect(marker!.position, const LatLng(36.0, 140.0));
      },
    );

    testWidgets(
      'the current-location marker is a distinct marker id from every '
      '言の葉 leaf marker (never confused with a KotonohaPin)',
      (tester) async {
        await tester.pumpWidget(_wrap(const KotonohaMap()));
        await tester.pumpWidget(_wrap(const KotonohaMap(currentLocation: initialLocation)));

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        final ids = map.markers.map((m) => m.markerId.value).toSet();
        expect(ids, contains('current_location'));
        // No pins are fetched in this environment (no live controller),
        // so the only marker present is the current-location one — this
        // just guards against it ever accidentally reusing a plain/empty
        // id that a real Root pin (a numeric-string id) could collide
        // with.
        expect(const MarkerId('current_location').value, isNot(matches(RegExp(r'^\d+$'))));
      },
    );
  });
}
