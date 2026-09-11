import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/connect_comment_input_screen.dart';
import 'package:kotonoha/screens/kotonoha_detail_screen.dart';
import 'package:kotonoha/services/location_service.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService.success(this._point) : _error = null;
  _FakeLocationService.failure(LocationFailureReason reason)
    : _point = null,
      _error = LocationServiceException(reason);

  final LocationPoint? _point;
  final LocationServiceException? _error;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    if (_error != null) throw _error;
    return _point!;
  }
}

const _item = KotonohaItem(
  id: '6',
  latitude: 35.0,
  longitude: 139.0,
  accuracy: 8.5,
  imageUrl: 'https://example.test/media/kotonoha/a.jpg',
  comment: '今日の空はきれい',
  createdAt: '2026-09-07T12:34:00+09:00',
);

void main() {
  testWidgets('builds with a photo, shows the comment and the created_at', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          locationService: _FakeLocationService.failure(
            LocationFailureReason.unknown,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('今日の空はきれい'), findsOneWidget);
    expect(find.text('2026/09/07 12:34'), findsOneWidget);
  });

  testWidgets('shows a loading state first, with 繋ぐ disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          locationService: _FakeLocationService.success(
            const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5),
          ),
        ),
      ),
    );

    expect(find.text('距離を確認しています…'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('at the same point (0m), shows 繋げる距離 and enables 繋ぐ', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          locationService: _FakeLocationService.success(
            const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('繋げる距離'), findsOneWidget);
    expect(find.text('あと 0m'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('tapping 繋ぐ while enabled opens ConnectCommentInputScreen '
      '(STEP11)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          locationService: _FakeLocationService.success(
            const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '繋ぐ'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectCommentInputScreen), findsOneWidget);
  });

  testWidgets('about 7m away (touchable), shows 触れられる距離 and keeps '
      '繋ぐ disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          // ~7.8m north of the item's location (0.00007 deg lat ~= 7.8m).
          locationService: _FakeLocationService.success(
            const LocationPoint(
              latitude: 35.00007,
              longitude: 139.0,
              accuracy: 5,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('触れられる距離'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('when location fails, shows an error and keeps 繋ぐ disabled '
      'without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KotonohaDetailScreen(
          item: _item,
          locationService: _FakeLocationService.failure(
            LocationFailureReason.serviceDisabled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('位置情報サービスがOFFになっています'),
      findsOneWidget,
    );
    // Still shows the photo/comment despite the location failure.
    expect(find.text('今日の空はきれい'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });
}
