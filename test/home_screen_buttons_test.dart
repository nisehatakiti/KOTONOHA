import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/home_screen.dart';
import 'package:kotonoha/services/kotonoha_api_service.dart';
import 'package:kotonoha/services/location_service.dart';
import 'package:kotonoha/widgets/kotonoha_map.dart';

class _FakeLocationService implements LocationService {
  int callCount = 0;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    callCount++;
    return const LocationPoint(
      latitude: 35.681236,
      longitude: 139.767125,
      accuracy: 12.5,
    );
  }
}

/// [gate], when supplied, holds fetchKotonohaRootDetail open until the test
/// completes it — used to inspect button state while a leaf is still
/// loading (_isLoadingSelected), before _selectedRoot ever resolves.
class _FakeApiService implements KotonohaApiService {
  _FakeApiService({this.gate});

  final Completer<void>? gate;

  @override
  Future<KotonohaRootDetail> fetchKotonohaRootDetail({
    required int id,
    double? latitude,
    double? longitude,
  }) async {
    if (gate != null) await gate!.future;
    return KotonohaRootDetail(
      root: KotonohaRootSummary(
        id: id.toString(),
        comment: 'テストの言の葉',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
  }

  @override
  Future<List<KotonohaPin>> fetchNearby({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async => const [];

  @override
  Future<List<KotonohaItem>> fetchKotonohaCluster(int id) async => const [];

  @override
  Future<KotonohaPostResult> postKotonoha({
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
    required File image,
  }) => throw UnimplementedError();

  @override
  Future<KotonohaPostResult> postConnectedKotonoha({
    required int parentId,
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
  }) => throw UnimplementedError();
}

/// GoogleMap is a platform view: `flutter test` never spins up the real
/// map SDK, so a marker can never be actually tapped here (see
/// kotonoha_map_test.dart's own header comment). Simulating "a leaf marker
/// was tapped" for this test means invoking KotonohaMap's own
/// [KotonohaMap.onLeafTap] callback directly, exactly as Google Maps
/// itself would end up doing via KotonohaMap's internal marker onTap ->
/// _handleMarkerTap -> onLeafTap chain.
Future<void> _tapLeaf(WidgetTester tester, String id) async {
  final map = tester.widget<KotonohaMap>(find.byType(KotonohaMap));
  map.onLeafTap!(id);
  await tester.pump();
}

ButtonStyleButton _updateMapButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '地図を更新'));

ButtonStyleButton _placeButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '言の葉を置く'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'both buttons stay enabled while nothing is selected',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            locationService: _FakeLocationService(),
            apiService: _FakeApiService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_updateMapButton(tester).onPressed, isNotNull);
      expect(_placeButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    '地図を更新/言の葉を置く are both disabled the moment a leaf popup opens '
    '(while still loading, before the detail fetch resolves)',
    (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            locationService: _FakeLocationService(),
            apiService: _FakeApiService(gate: gate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapLeaf(tester, '1');

      expect(_updateMapButton(tester).onPressed, isNull);
      expect(_placeButton(tester).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'both buttons remain disabled once the popup finishes loading, and '
    're-enable automatically once the popup is closed (tap-outside -> '
    'onMapTap -> _clearSelection)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            locationService: _FakeLocationService(),
            apiService: _FakeApiService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapLeaf(tester, '1');
      await tester.pumpAndSettle();

      expect(_updateMapButton(tester).onPressed, isNull);
      expect(_placeButton(tester).onPressed, isNull);

      // The popup's own close action (KotonohaMap's tap-to-close layer,
      // wired to onMapTap) must stay usable throughout — verified here by
      // calling it exactly as that layer would.
      final map = tester.widget<KotonohaMap>(find.byType(KotonohaMap));
      map.onMapTap!();
      await tester.pumpAndSettle();

      expect(_updateMapButton(tester).onPressed, isNotNull);
      expect(_placeButton(tester).onPressed, isNotNull);
    },
  );
}
