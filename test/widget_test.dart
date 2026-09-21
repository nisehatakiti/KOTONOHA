import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/home_screen.dart';
import 'package:kotonoha/services/location_service.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService.success()
    : _result = const LocationPoint(
        latitude: 35.681236,
        longitude: 139.767125,
        accuracy: 12.5,
      ),
      _error = null;

  _FakeLocationService.failure(LocationFailureReason reason)
    : _result = null,
      _error = LocationServiceException(reason);

  final LocationPoint? _result;
  final LocationServiceException? _error;

  int callCount = 0;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    callCount++;
    if (_error != null) throw _error;
    return _result!;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home screen shows the two primary actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(locationService: _FakeLocationService.success()),
      ),
    );

    expect(find.text('地図を更新'), findsOneWidget);
    expect(find.text('言の葉を置く'), findsOneWidget);
  });

  testWidgets(
    '地図を更新 fetches the current location and shows the confirmation '
    'snackbar (real-device UI pass: the 緯度/経度/精度 debug readout is no '
    'longer shown — see _LocationDebugPanel in home_screen.dart; the '
    'underlying fetch itself is unchanged)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(locationService: _FakeLocationService.success()),
        ),
      );

      await tester.tap(find.text('地図を更新'));
      await tester.pumpAndSettle();

      expect(find.text('地図を更新しました'), findsOneWidget);
      expect(find.textContaining('緯度:'), findsNothing);
      expect(find.textContaining('精度:'), findsNothing);
    },
  );

  testWidgets('地図を更新 shows an error when the location service is off', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          locationService: _FakeLocationService.failure(
            LocationFailureReason.serviceDisabled,
          ),
        ),
      ),
    );

    await tester.tap(find.text('地図を更新'));
    await tester.pumpAndSettle();

    expect(find.textContaining('位置情報サービスがOFFになっています'), findsWidgets);
  });

  testWidgets(
    'STEP12 14-4/7: location is fetched once automatically on launch, '
    'without the button being tapped and without a "地図を更新しました" '
    'snackbar (that stays button-only)',
    (WidgetTester tester) async {
      final locationService = _FakeLocationService.success();

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(locationService: locationService)),
      );
      await tester.pumpAndSettle();

      expect(locationService.callCount, 1);
      // Real-device UI pass: the 緯度/経度/精度 debug readout is gone —
      // the location fetch itself (callCount above) is what this test is
      // really verifying, and that's unchanged.
      expect(find.textContaining('緯度:'), findsNothing);
      expect(find.text('地図を更新しました'), findsNothing);
    },
  );

  testWidgets(
    'STEP12 14-5: a location failure on launch does not crash and shows '
    'the existing error UI without any lat/lng ever appearing',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            locationService: _FakeLocationService.failure(
              LocationFailureReason.serviceDisabled,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('位置情報サービスがOFFになっています'), findsWidgets);
      expect(find.textContaining('緯度:'), findsNothing);
      // The screen is still fully usable — both primary actions remain.
      expect(find.text('地図を更新'), findsOneWidget);
      expect(find.text('言の葉を置く'), findsOneWidget);
    },
  );
}
