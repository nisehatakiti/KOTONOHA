import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:kotonoha/services/kotonoha_api_service.dart';

class _StubClient extends http.BaseClient {
  _StubClient(this._respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _respond(request);
}

http.StreamedResponse _jsonResponse(int statusCode, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  // Without an explicit charset, package:http defaults .body to latin1,
  // mangling non-ASCII content — matches the real server, which always
  // sends "charset=utf-8" (see JsonResponse::send in KOTONOHA-API).
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.StreamedResponse _rawResponse(int statusCode, String body) {
  return http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);
}

void main() {
  group('fetchNearby', () {
    test('parses items into KotonohaPin and sends the bounds as query '
        'parameters', () async {
      Uri? capturedUri;
      final client = _StubClient((request) async {
        capturedUri = request.url;
        return _jsonResponse(200, {
          'success': true,
          'items': [
            {
              'id': 1,
              'latitude': 35.681236,
              'longitude': 139.767125,
              'created_at': '2026-09-05T16:57:14+09:00',
            },
          ],
        });
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final pins = await service.fetchNearby(
        north: 35.70,
        south: 35.60,
        east: 139.80,
        west: 139.60,
      );

      expect(pins, hasLength(1));
      expect(pins.single.id, '1');
      expect(pins.single.latitude, 35.681236);
      expect(pins.single.longitude, 139.767125);

      expect(capturedUri!.path, '/api/kotonoha');
      expect(capturedUri!.queryParameters['north'], '35.7');
      expect(capturedUri!.queryParameters['south'], '35.6');
      expect(capturedUri!.queryParameters['east'], '139.8');
      expect(capturedUri!.queryParameters['west'], '139.6');
    });

    test('returns an empty list when items is empty', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(200, {'success': true, 'items': []}),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final pins = await service.fetchNearby(
        north: 1,
        south: 0,
        east: 1,
        west: 0,
      );

      expect(pins, isEmpty);
    });

    test('STEP12 14-3 (defensive): an item carrying a parent_id is still '
        'parsed as a plain pin — there is no parent_id-based filtering or '
        'special-casing on the Flutter side, since the server already '
        'guarantees Root-only results', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(200, {
          'success': true,
          'items': [
            {
              'id': 5,
              'parent_id': 999,
              'latitude': 35.0,
              'longitude': 139.0,
              'created_at': '2026-09-05T16:57:14+09:00',
            },
          ],
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final pins = await service.fetchNearby(
        north: 36,
        south: 34,
        east: 140,
        west: 138,
      );

      // Parsed exactly like any other item — KotonohaPin has no field to
      // even represent parent_id, so nothing can promote/demote it based
      // on one.
      expect(pins, hasLength(1));
      expect(pins.single.id, '5');
      expect(pins.single.latitude, 35.0);
      expect(pins.single.longitude, 139.0);
    });

    test('throws KotonohaApiException on a 400 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(400, {
          'error': {
            'code': 'INVALID_LOCATION',
            'message': 'north must be greater than south.',
          },
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchNearby(north: 0, south: 1, east: 1, west: 0),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.invalidRequest,
          ),
        ),
      );
    });

    test('throws a server-reason KotonohaApiException on a 500 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(500, {
          'error': {'code': 'SERVER_ERROR', 'message': 'boom'},
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchNearby(north: 1, south: 0, east: 1, west: 0),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.server,
          ),
        ),
      );
    });
  });

  group('fetchKotonohaCluster', () {
    test('parses items into KotonohaItem, hitting /api/kotonoha/{id}', () async {
      Uri? capturedUri;
      final client = _StubClient((request) async {
        capturedUri = request.url;
        return _jsonResponse(200, {
          'success': true,
          'items': [
            {
              'id': 6,
              'latitude': 35.5,
              'longitude': 139.5,
              'accuracy': 8.5,
              'image_url': 'https://example.test/media/kotonoha/a.jpg',
              'comment': '今日の空はきれい',
              'created_at': '2026-09-06T20:33:19+09:00',
            },
          ],
        });
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final items = await service.fetchKotonohaCluster(6);

      expect(items, hasLength(1));
      expect(items.single.id, '6');
      expect(items.single.comment, '今日の空はきれい');
      expect(
        items.single.imageUrl,
        'https://example.test/media/kotonoha/a.jpg',
      );
      expect(capturedUri!.path, '/api/kotonoha/6');
    });

    test('throws a notFound KotonohaApiException on a 404 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(404, {
          'error': {'code': 'NOT_FOUND', 'message': 'kotonoha not found.'},
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaCluster(999999),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.notFound,
          ),
        ),
      );
    });

    test('throws a server-reason KotonohaApiException on a 500 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(500, {
          'error': {'code': 'SERVER_ERROR', 'message': 'boom'},
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaCluster(1),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.server,
          ),
        ),
      );
    });

    test('throws a network-reason KotonohaApiException on a connection '
        'failure', () async {
      final client = _StubClient((request) async {
        throw const SocketExceptionStub();
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaCluster(1),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.network,
          ),
        ),
      );
    });

    test('throws an invalidRequest KotonohaApiException on malformed JSON', () async {
      final client = _StubClient(
        (request) async => _rawResponse(200, 'not valid json'),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaCluster(1),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.invalidRequest,
          ),
        ),
      );
    });
  });

  group('fetchKotonohaRootDetail (STEP11-UI (A)/(B) fix)', () {
    test('near: sends lat/lng as query params and parses root + '
        'connections', () async {
      Uri? capturedUri;
      final client = _StubClient((request) async {
        capturedUri = request.url;
        return _jsonResponse(200, {
          'success': true,
          'root': {
            'id': 6,
            'latitude': 35.5,
            'longitude': 139.5,
            'accuracy': 8.5,
            'comment': '今日の空はきれい',
            'created_at': '2026-09-06T20:33:19+09:00',
            'image_url': 'https://example.test/media/kotonoha/a.jpg',
          },
          'connections': [
            {
              'id': 10,
              'parent_id': 6,
              'comment': '空がすごく青い',
              'created_at': '2026-09-06T20:40:00+09:00',
            },
          ],
        });
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final detail = await service.fetchKotonohaRootDetail(
        id: 6,
        latitude: 35.5,
        longitude: 139.5,
      );

      expect(capturedUri!.path, '/api/kotonoha/6');
      expect(capturedUri!.queryParameters['latitude'], '35.5');
      expect(capturedUri!.queryParameters['longitude'], '139.5');

      expect(detail.root.id, '6');
      expect(detail.root.comment, '今日の空はきれい');
      expect(detail.root.latitude, 35.5);
      expect(detail.root.longitude, 139.5);
      expect(detail.root.accuracy, 8.5);
      expect(
        detail.root.imageUrl,
        'https://example.test/media/kotonoha/a.jpg',
      );
      expect(detail.connections, hasLength(1));
      expect(detail.connections.single.id, '10');
      expect(detail.connections.single.parentId, '6');
      expect(detail.connections.single.comment, '空がすごく青い');
    });

    test('far (or unknown location): no query params when lat/lng are '
        'omitted, and parses a root-only response (no photo/connections/'
        'coordinates present at all)', () async {
      Uri? capturedUri;
      final client = _StubClient((request) async {
        capturedUri = request.url;
        return _jsonResponse(200, {
          'success': true,
          'root': {
            'id': 6,
            'comment': '今日の空はきれい',
            'created_at': '2026-09-06T20:33:19+09:00',
          },
        });
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      final detail = await service.fetchKotonohaRootDetail(id: 6);

      expect(capturedUri!.queryParameters, isEmpty);
      expect(detail.root.id, '6');
      expect(detail.root.comment, '今日の空はきれい');
      expect(detail.root.latitude, isNull);
      expect(detail.root.longitude, isNull);
      expect(detail.root.accuracy, isNull);
      expect(detail.root.imageUrl, isNull);
      expect(detail.connections, isEmpty);
    });

    test('throws a notFound KotonohaApiException on a 404 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(404, {
          'error': {'code': 'NOT_FOUND', 'message': 'kotonoha not found.'},
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaRootDetail(id: 999999),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.notFound,
          ),
        ),
      );
    });

    test('throws a network-reason KotonohaApiException on a connection '
        'failure', () async {
      final client = _StubClient((request) async {
        throw const SocketExceptionStub();
      });
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaRootDetail(id: 6),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.network,
          ),
        ),
      );
    });

    test('throws a server-reason KotonohaApiException on a 500 response', () async {
      final client = _StubClient(
        (request) async => _jsonResponse(500, {
          'error': {'code': 'SERVER_ERROR', 'message': 'boom'},
        }),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaRootDetail(id: 6),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.server,
          ),
        ),
      );
    });

    test('throws an invalidRequest KotonohaApiException on malformed JSON', () async {
      final client = _StubClient(
        (request) async => _rawResponse(200, 'not valid json'),
      );
      final service = KotonohaApiService(
        baseUrl: 'https://example.test',
        client: client,
      );

      await expectLater(
        service.fetchKotonohaRootDetail(id: 6),
        throwsA(
          isA<KotonohaApiException>().having(
            (e) => e.reason,
            'reason',
            KotonohaApiFailureReason.invalidRequest,
          ),
        ),
      );
    });
  });
}

/// Stands in for a real network failure (e.g. SocketException) without
/// depending on dart:io in this test.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
