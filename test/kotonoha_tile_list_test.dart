import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/services/kotonoha_api_service.dart';
import 'package:kotonoha/widgets/kotonoha_tile_list.dart';

class _FakeApiService implements KotonohaApiService {
  _FakeApiService({List<KotonohaApiException> failThenSucceed = const []})
    : _remainingFailures = List.of(failThenSucceed);

  final List<KotonohaApiException> _remainingFailures;
  int callCount = 0;

  static const _items = [
    KotonohaItem(
      id: '6',
      latitude: 35.5,
      longitude: 139.5,
      accuracy: 8.5,
      imageUrl: null,
      comment: 'テストの言の葉',
      createdAt: '2026-09-06T20:33:19+09:00',
    ),
  ];

  @override
  Future<List<KotonohaItem>> fetchKotonohaCluster(int id) async {
    callCount++;
    if (_remainingFailures.isNotEmpty) {
      throw _remainingFailures.removeAt(0);
    }
    return _items;
  }

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
  testWidgets('shows a loading indicator, then the tile grid on success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KotonohaTileListSheet(id: '6', apiService: _FakeApiService()),
        ),
      ),
    );

    // Before the Future resolves: loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('テストの言の葉'), findsOneWidget);
  });

  testWidgets('shows an error with a retry button, then the tile grid after '
      'a successful retry', (tester) async {
    final apiService = _FakeApiService(
      failThenSucceed: [
        KotonohaApiException(KotonohaApiFailureReason.server, 'boom'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KotonohaTileListSheet(id: '6', apiService: apiService),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('読み込みに失敗しました'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    expect(find.text('テストの言の葉'), findsNothing);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(find.text('テストの言の葉'), findsOneWidget);
    expect(apiService.callCount, 2);
  });

  testWidgets('shows a "not found" message without a retry button on a 404', (
    tester,
  ) async {
    final apiService = _FakeApiService(
      failThenSucceed: [
        KotonohaApiException(
          KotonohaApiFailureReason.notFound,
          'not found',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KotonohaTileListSheet(id: '999999', apiService: apiService),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('この言の葉は見つかりませんでした'), findsOneWidget);
    expect(find.text('再試行'), findsNothing);
  });
}
