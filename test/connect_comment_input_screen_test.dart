import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/connect_comment_input_screen.dart';
import 'package:kotonoha/services/installation_id_service.dart';
import 'package:kotonoha/services/kotonoha_api_service.dart';
import 'package:kotonoha/services/location_service.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService.success()
    : _point = const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5),
      _error = null;

  _FakeLocationService.failure(LocationFailureReason reason)
    : _point = null,
      _error = LocationServiceException(reason);

  final LocationPoint? _point;
  final LocationServiceException? _error;

  int callCount = 0;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    callCount++;
    if (_error != null) throw _error;
    return _point!;
  }
}

class _FakeInstallationIdService implements InstallationIdService {
  @override
  Future<String> getInstallationId() async => 'test-installation-id';
}

class _FakeApiService implements KotonohaApiService {
  _FakeApiService.success()
    : _result = const KotonohaPostResult(id: 42, createdAt: '2026-01-01 00:00:00'),
      _error = null;

  _FakeApiService.failure(KotonohaApiFailureReason reason, String message)
    : _result = null,
      _error = KotonohaApiException(reason, message);

  final KotonohaPostResult? _result;
  final KotonohaApiException? _error;

  String? capturedComment;
  int callCount = 0;

  @override
  Future<KotonohaPostResult> postConnectedKotonoha({
    required int parentId,
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
  }) async {
    callCount++;
    capturedComment = comment;
    if (_error != null) throw _error;
    return _result!;
  }

  @override
  Future<List<KotonohaItem>> fetchKotonohaCluster(int id) async => const [];

  @override
  Future<KotonohaRootDetail> fetchKotonohaRootDetail({
    required int id,
    double? latitude,
    double? longitude,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<KotonohaPin>> fetchNearby({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async => const [];

  @override
  Future<KotonohaPostResult> postKotonoha({
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
    required File image,
  }) {
    throw UnimplementedError();
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('empty comment disables the 繋ぐ button', (tester) async {
    await tester.pumpWidget(
      _wrap(const ConnectCommentInputScreen(parentId: 1)),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('whitespace-only comment disables the 繋ぐ button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ConnectCommentInputScreen(parentId: 1)),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('50 characters can be entered and enable the button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ConnectCommentInputScreen(parentId: 1)),
    );

    await tester.enterText(find.byType(TextField), 'あ' * 50);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 50);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('51 characters cannot be entered (input is capped at 50)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ConnectCommentInputScreen(parentId: 1)),
    );

    await tester.enterText(find.byType(TextField), 'あ' * 51);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 50);
  });

  testWidgets(
    'successful connect shows a success dialog and pops with true',
    (tester) async {
      final apiService = _FakeApiService.success();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ConnectCommentInputScreen(
                          parentId: 1,
                          locationService: _FakeLocationService.success(),
                          installationIdService: _FakeInstallationIdService(),
                          apiService: apiService,
                        ),
                      ),
                    );
                    lastResult = result;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'こんにちは');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('言の葉を繋ぎました'), findsOneWidget);
      expect(apiService.capturedComment, 'こんにちは');

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(lastResult, isTrue);
    },
  );

  testWidgets(
    'location failure does not call the API, shows an error, and keeps '
    'the comment',
    (tester) async {
      final apiService = _FakeApiService.success();
      final locationService = _FakeLocationService.failure(
        LocationFailureReason.serviceDisabled,
      );

      await tester.pumpWidget(
        _wrap(
          ConnectCommentInputScreen(
            parentId: 1,
            locationService: locationService,
            installationIdService: _FakeInstallationIdService(),
            apiService: apiService,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'こんにちは');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('位置情報サービスがOFFになっています'),
        findsOneWidget,
      );
      expect(apiService.callCount, 0);
      expect(find.text('こんにちは'), findsOneWidget);
    },
  );

  testWidgets('a network error keeps the comment and shows an error', (
    tester,
  ) async {
    final apiService = _FakeApiService.failure(
      KotonohaApiFailureReason.network,
      'ネットワークに接続できませんでした。',
    );

    await tester.pumpWidget(
      _wrap(
        ConnectCommentInputScreen(
          parentId: 1,
          locationService: _FakeLocationService.success(),
          installationIdService: _FakeInstallationIdService(),
          apiService: apiService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'こんにちは');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('ネットワークに接続できませんでした'), findsOneWidget);
    expect(find.text('こんにちは'), findsOneWidget);
  });

  testWidgets('a distance-too-far error keeps the comment and shows an '
      'error', (tester) async {
    final apiService = _FakeApiService.failure(
      KotonohaApiFailureReason.invalidRequest,
      'この言の葉から5m以内に近づいてから繋いでください。',
    );

    await tester.pumpWidget(
      _wrap(
        ConnectCommentInputScreen(
          parentId: 1,
          locationService: _FakeLocationService.success(),
          installationIdService: _FakeInstallationIdService(),
          apiService: apiService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'こんにちは');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('5m以内に近づいてから'), findsOneWidget);
    expect(find.text('こんにちは'), findsOneWidget);
  });

  testWidgets('parent not-found does not crash and keeps the screen usable', (
    tester,
  ) async {
    final apiService = _FakeApiService.failure(
      KotonohaApiFailureReason.notFound,
      'この言の葉は見つかりませんでした。',
    );

    await tester.pumpWidget(
      _wrap(
        ConnectCommentInputScreen(
          parentId: 1,
          locationService: _FakeLocationService.success(),
          installationIdService: _FakeInstallationIdService(),
          apiService: apiService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'こんにちは');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('見つかりませんでした'), findsOneWidget);
    expect(find.byType(ConnectCommentInputScreen), findsOneWidget);
  });

  testWidgets('double-tapping 繋ぐ only sends one request', (tester) async {
    final apiService = _FakeApiService.success();

    await tester.pumpWidget(
      _wrap(
        ConnectCommentInputScreen(
          parentId: 1,
          locationService: _FakeLocationService.success(),
          installationIdService: _FakeInstallationIdService(),
          apiService: apiService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'こんにちは');
    await tester.pump();

    // First tap starts the async post and disables the button before the
    // second tap can land — it's expected to miss the (now-disabled)
    // button, which is exactly what proves only one request was sent.
    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(apiService.callCount, 1);
  });
}

bool? lastResult;
