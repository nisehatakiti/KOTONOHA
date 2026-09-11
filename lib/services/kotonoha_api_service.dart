import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/kotonoha_item.dart';
import '../models/kotonoha_pin.dart';
import '../models/kotonoha_root_detail.dart';
import 'api_config.dart';

/// Why a `POST /api/kotonoha` call failed, so the UI can show a specific,
/// actionable message and decide whether retrying makes sense (docs/ui.md:
/// 位置情報取得失敗・ネットワークエラー・429・サーバーエラーを分けて表示).
enum KotonohaApiFailureReason {
  network,
  cooldown,
  invalidRequest,
  server,

  /// `GET /api/kotonoha/{id}` returned 404 — the tapped 言の葉 doesn't
  /// exist (or was deleted after the map pin was fetched). Distinct from
  /// [server]/[invalidRequest] because the UI shows "見つかりませんでした"
  /// instead of a retry button for this case (STEP10-A spec).
  notFound,
}

class KotonohaApiException implements Exception {
  KotonohaApiException(this.reason, this.message);

  final KotonohaApiFailureReason reason;
  final String message;
}

class KotonohaPostResult {
  const KotonohaPostResult({required this.id, required this.createdAt});

  final int id;
  final String createdAt;
}

/// Talks to `POST /api/kotonoha` (see the KOTONOHA-API repository,
/// docs/api.md section 5). Distance/rate-limit checks are never done here
/// — only the server decides those (docs/api.md section 10).
class KotonohaApiService {
  KotonohaApiService({String? baseUrl, http.Client? client})
    : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<KotonohaPostResult> postKotonoha({
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
    required File image,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/kotonoha');
    final request = http.MultipartRequest('POST', uri)
      ..fields['installation_id'] = installationId
      ..fields['latitude'] = latitude.toString()
      ..fields['longitude'] = longitude.toString()
      ..fields['accuracy'] = accuracy.toString()
      ..fields['comment'] = comment
      ..files.add(await http.MultipartFile.fromPath('image', image.path));

    final http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.network,
        'ネットワークに接続できませんでした。電波状況を確認してもう一度お試しください。',
      );
    }

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return KotonohaPostResult(
        id: body['id'] as int,
        createdAt: body['created_at'] as String,
      );
    }

    final serverMessage = _extractErrorMessage(response.body);

    if (response.statusCode == 429) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.cooldown,
        serverMessage ?? '言の葉を置いてから5分間は次を置けません。しばらくお待ちください。',
      );
    }

    if (response.statusCode >= 500) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.server,
        serverMessage ?? 'サーバーでエラーが発生しました。しばらくしてからもう一度お試しください。',
      );
    }

    throw KotonohaApiException(
      KotonohaApiFailureReason.invalidRequest,
      serverMessage ?? '入力内容を確認してください。',
    );
  }

  /// `GET /api/kotonoha` (see the KOTONOHA-API repository): 言の葉 within
  /// the given map bounds, for marker display only — no comment/photo/
  /// installation_id is included in this response.
  Future<List<KotonohaPin>> fetchNearby({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/kotonoha').replace(
      queryParameters: {
        'north': north.toString(),
        'south': south.toString(),
        'east': east.toString(),
        'west': west.toString(),
      },
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.network,
        'ネットワークに接続できませんでした。',
      );
    }

    if (response.statusCode != 200) {
      final serverMessage = _extractErrorMessage(response.body);
      throw KotonohaApiException(
        response.statusCode >= 500
            ? KotonohaApiFailureReason.server
            : KotonohaApiFailureReason.invalidRequest,
        serverMessage ?? '言の葉の取得に失敗しました。',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'] as List<dynamic>? ?? const [];
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        KotonohaPin(
          id: item['id'].toString(),
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
        ),
    ];
  }

  /// `GET /api/kotonoha/{id}` (STEP10-A shape: `{"items": [...]}`,
  /// spatial "same spot" clustering).
  ///
  /// STEP11-UI (A)/(B) fix: the server no longer responds in this shape —
  /// `GET /api/kotonoha/{id}` now returns `{"root": ..., "connections":
  /// [...]}"` via [fetchKotonohaRootDetail], which callers should use
  /// instead. Kept only because [KotonohaTileListSheet] (STEP10-A, no
  /// longer part of the live pin-tap flow — see HomeScreen) still calls
  /// it; against the real API it now just parses an empty `items` list
  /// (no crash, `?? const []` below), since that key no longer exists in
  /// the response. Not used by any reachable screen.
  Future<List<KotonohaItem>> fetchKotonohaCluster(int id) async {
    final uri = Uri.parse('$_baseUrl/api/kotonoha/$id');

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.network,
        'ネットワークに接続できませんでした。',
      );
    }

    if (response.statusCode == 404) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.notFound,
        'この言の葉は見つかりませんでした。',
      );
    }

    if (response.statusCode != 200) {
      final serverMessage = _extractErrorMessage(response.body);
      throw KotonohaApiException(
        response.statusCode >= 500
            ? KotonohaApiFailureReason.server
            : KotonohaApiFailureReason.invalidRequest,
        serverMessage ?? '言の葉の取得に失敗しました。',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.invalidRequest,
        '言の葉の取得に失敗しました。',
      );
    }

    final items = body['items'] as List<dynamic>? ?? const [];
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        KotonohaItem(
          id: item['id'].toString(),
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
          accuracy: (item['accuracy'] as num).toDouble(),
          imageUrl: item['image_url'] as String?,
          comment: item['comment'] as String,
          createdAt: item['created_at'] as String,
        ),
    ];
  }

  /// `GET /api/kotonoha/{id}` (STEP11-UI (A)/(B) fix): the Root post [id]
  /// and, only when the server determines [latitude]/[longitude] are
  /// within 5m of it, its photo and connect-post comments. Passing no
  /// location (or a null pair) is a valid, safe call — the server treats
  /// it the same as ">5m" and returns only the Root's comment/date, never
  /// an error (docs/api.md GET /api/kotonoha/{id} section 8).
  ///
  /// The server — not this method, not the caller — decides what "near"
  /// means; a client-computed distance is never sent or trusted for
  /// access control (docs/api.md section 10).
  Future<KotonohaRootDetail> fetchKotonohaRootDetail({
    required int id,
    double? latitude,
    double? longitude,
  }) async {
    final hasLocation = latitude != null && longitude != null;
    final uri = Uri.parse('$_baseUrl/api/kotonoha/$id').replace(
      queryParameters: hasLocation
          ? {'latitude': latitude.toString(), 'longitude': longitude.toString()}
          : null,
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.network,
        'ネットワークに接続できませんでした。',
      );
    }

    if (response.statusCode == 404) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.notFound,
        'この言の葉は見つかりませんでした。',
      );
    }

    if (response.statusCode != 200) {
      final serverMessage = _extractErrorMessage(response.body);
      throw KotonohaApiException(
        response.statusCode >= 500
            ? KotonohaApiFailureReason.server
            : KotonohaApiFailureReason.invalidRequest,
        serverMessage ?? '言の葉の取得に失敗しました。',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.invalidRequest,
        '言の葉の取得に失敗しました。',
      );
    }

    final rootJson = body['root'] as Map<String, dynamic>;
    final root = KotonohaRootSummary(
      id: rootJson['id'].toString(),
      comment: rootJson['comment'] as String,
      createdAt: rootJson['created_at'] as String,
      latitude: (rootJson['latitude'] as num?)?.toDouble(),
      longitude: (rootJson['longitude'] as num?)?.toDouble(),
      accuracy: (rootJson['accuracy'] as num?)?.toDouble(),
      imageUrl: rootJson['image_url'] as String?,
    );

    final connectionsJson = body['connections'] as List<dynamic>? ?? const [];
    final connections = [
      for (final item in connectionsJson.cast<Map<String, dynamic>>())
        KotonohaConnection(
          id: item['id'].toString(),
          parentId: item['parent_id'].toString(),
          comment: item['comment'] as String,
          createdAt: item['created_at'] as String,
        ),
    ];

    return KotonohaRootDetail(root: root, connections: connections);
  }

  /// `POST /api/kotonoha` with `parent_id` set (STEP11: 言の葉を繋ぐ) —
  /// no image is ever sent for a connect post. The server re-verifies the
  /// parent's existence/deleted-state and the 5m distance itself; this
  /// method never assumes the Flutter-side distance check is authoritative
  /// (docs/api.md section 10).
  Future<KotonohaPostResult> postConnectedKotonoha({
    required int parentId,
    required String installationId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String comment,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/kotonoha');
    final request = http.MultipartRequest('POST', uri)
      ..fields['installation_id'] = installationId
      ..fields['latitude'] = latitude.toString()
      ..fields['longitude'] = longitude.toString()
      ..fields['accuracy'] = accuracy.toString()
      ..fields['comment'] = comment
      ..fields['parent_id'] = parentId.toString();

    final http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.network,
        'ネットワークに接続できませんでした。電波状況を確認してもう一度お試しください。',
      );
    }

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return KotonohaPostResult(
        id: body['id'] as int,
        createdAt: body['created_at'] as String,
      );
    }

    if (response.statusCode == 404) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.notFound,
        'この言の葉は見つかりませんでした。',
      );
    }

    final errorCode = _extractErrorCode(response.body);
    if (errorCode == 'DISTANCE_TOO_FAR') {
      throw KotonohaApiException(
        KotonohaApiFailureReason.invalidRequest,
        'この言の葉から5m以内に近づいてから繋いでください。',
      );
    }

    final serverMessage = _extractErrorMessage(response.body);

    if (response.statusCode >= 500) {
      throw KotonohaApiException(
        KotonohaApiFailureReason.server,
        serverMessage ?? '投稿に失敗しました。時間をおいて再試行してください。',
      );
    }

    throw KotonohaApiException(
      KotonohaApiFailureReason.invalidRequest,
      serverMessage ?? '入力内容を確認してください。',
    );
  }

  String? _extractErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final code = error['code'];
          if (code is String) return code;
        }
      }
    } catch (_) {
      // Malformed/non-JSON body: fall back to generic handling.
    }
    return null;
  }

  String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String) return message;
        }
      }
    } catch (_) {
      // Malformed/non-JSON body: fall back to the caller's default message.
    }
    return null;
  }
}
