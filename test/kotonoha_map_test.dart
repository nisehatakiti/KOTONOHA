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

  // Real-device fix (2nd round): a current-location marker was added in an
  // earlier round, then explicitly removed again — no pin of any kind may
  // ever represent "現在地" on the map. GoogleMapController isn't created in
  // this test environment (see this file's own header comment), so
  // refreshCurrentLocation's camera-move/nearby-refetch behavior itself
  // can't be exercised here — only that no marker ever appears, and that
  // calling refreshCurrentLocation (with no live controller) doesn't throw.
  group('no current-location marker (real-device fix, removed again)', () {
    const initialLocation = LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5);
    const updatedLocation = LocationPoint(latitude: 36.0, longitude: 140.0, accuracy: 5);

    bool hasCurrentLocationMarker(WidgetTester tester) {
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      return map.markers.any((m) => m.markerId == const MarkerId('current_location'));
    }

    testWidgets('no marker before any location is known', (tester) async {
      await tester.pumpWidget(_wrap(const KotonohaMap()));

      expect(hasCurrentLocationMarker(tester), isFalse);
    });

    testWidgets(
      'still no marker once the very first location arrives (app launch: '
      'null -> non-null)',
      (tester) async {
        // Mirrors HomeScreen's own real sequence: KotonohaMap is first
        // built with no location at all, then rebuilt once the initial
        // fetch resolves — didUpdateWidget's own null->non-null branch is
        // what this exercises.
        await tester.pumpWidget(_wrap(const KotonohaMap()));
        await tester.pumpWidget(_wrap(const KotonohaMap(currentLocation: initialLocation)));

        expect(hasCurrentLocationMarker(tester), isFalse);
      },
    );

    testWidgets(
      'refreshCurrentLocation (the "地図を更新" direct call path) still '
      'draws no marker, and does not throw with no live controller',
      (tester) async {
        final mapKey = GlobalKey<KotonohaMapState>();
        await tester.pumpWidget(_wrap(KotonohaMap(key: mapKey)));
        await tester.pumpWidget(
          _wrap(KotonohaMap(key: mapKey, currentLocation: initialLocation)),
        );
        expect(hasCurrentLocationMarker(tester), isFalse);

        await mapKey.currentState!.refreshCurrentLocation(updatedLocation);
        await tester.pump();

        expect(hasCurrentLocationMarker(tester), isFalse);
      },
    );
  });

  group(
    '実機修正: unwanted standard Google Maps chrome is disabled — '
    'KOTONOHA never designed for the directions/open-in-Maps-app '
    'toolbar, the compass, or the indoor floor picker',
    () {
      testWidgets('mapToolbarEnabled / compassEnabled / indoorViewEnabled are all false', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(const KotonohaMap()));

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.mapToolbarEnabled, isFalse);
        expect(map.compassEnabled, isFalse);
        expect(map.indoorViewEnabled, isFalse);
      });

      testWidgets(
        'already-disabled chrome (myLocationButtonEnabled/'
        'zoomControlsEnabled) is still disabled — not reverted by this '
        'change',
        (tester) async {
          await tester.pumpWidget(_wrap(const KotonohaMap()));

          final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
          expect(map.myLocationButtonEnabled, isFalse);
          expect(map.zoomControlsEnabled, isFalse);
        },
      );

      testWidgets(
        "KOTONOHA's own controls (pan/pinch-zoom when nothing is "
        'selected) are unaffected by disabling Google\'s own chrome',
        (tester) async {
          await tester.pumpWidget(_wrap(const KotonohaMap()));

          final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
          expect(map.scrollGesturesEnabled, isTrue);
          expect(map.zoomGesturesEnabled, isTrue);
        },
      );
    },
  );
}
