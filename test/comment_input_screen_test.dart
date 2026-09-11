import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/comment_input_screen.dart';
import 'package:kotonoha/services/installation_id_service.dart';
import 'package:kotonoha/services/kotonoha_api_service.dart';
import 'package:kotonoha/services/location_service.dart';

// Minimal valid 1x1 transparent PNG, so Image.file has real bytes to decode.
const _minimalPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _FakeLocationService implements LocationService {
  @override
  Future<LocationPoint> getCurrentLocation() async {
    return const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5);
  }
}

class _FailingLocationService implements LocationService {
  @override
  Future<LocationPoint> getCurrentLocation() async {
    throw LocationServiceException(LocationFailureReason.serviceDisabled);
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

  @override
  Future<KotonohaPostResult> postKotonoha({
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
    required File image,
  }) async {
    if (_error != null) throw _error;
    return _result!;
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
  Future<KotonohaRootDetail> fetchKotonohaRootDetail({
    required int id,
    double? latitude,
    double? longitude,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<KotonohaPostResult> postConnectedKotonoha({
    required int parentId,
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  late Directory tempDir;
  late XFile testPhoto;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kotonoha_test');
    final file = File('${tempDir.path}/photo.png');
    await file.writeAsBytes(base64Decode(_minimalPngBase64));
    testPhoto = XFile(file.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('empty comment disables the proceed button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CommentInputScreen(photo: testPhoto)),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('comment field accepts up to 50 characters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CommentInputScreen(photo: testPhoto)),
    );
    await tester.pumpAndSettle();

    final comment = 'あ' * 50;
    await tester.enterText(find.byType(TextField), comment);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 50);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('comment field blocks more than 50 characters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CommentInputScreen(photo: testPhoto)),
    );
    await tester.pumpAndSettle();

    final overLong = 'あ' * 51;
    await tester.enterText(find.byType(TextField), overLong);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 50);
  });

  testWidgets(
    'placing successfully re-fetches location, posts, and returns to the '
    'first route',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CommentInputScreen(
                        photo: testPhoto,
                        locationService: _FakeLocationService(),
                        installationIdService: _FakeInstallationIdService(),
                        apiService: _FakeApiService.success(),
                      ),
                    ),
                  ),
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

      expect(find.text('言の葉を置きました'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.byType(CommentInputScreen), findsNothing);
    },
  );

  testWidgets(
    'a location failure while placing shows an error and lets the user '
    'retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommentInputScreen(
            photo: testPhoto,
            locationService: _FailingLocationService(),
            installationIdService: _FakeInstallationIdService(),
            apiService: _FakeApiService.success(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'こんにちは');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('位置情報サービスがOFFになっています'),
        findsOneWidget,
      );
      // Still on this screen, and the button is enabled again for a retry.
      expect(find.byType(CommentInputScreen), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'a 429 cooldown response from the API shows an error and lets the '
    'user retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommentInputScreen(
            photo: testPhoto,
            locationService: _FakeLocationService(),
            installationIdService: _FakeInstallationIdService(),
            apiService: _FakeApiService.failure(
              KotonohaApiFailureReason.cooldown,
              '5分間は次を置けません。',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'こんにちは');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('5分間は次を置けません'), findsOneWidget);
      expect(find.byType(CommentInputScreen), findsOneWidget);
    },
  );
}
