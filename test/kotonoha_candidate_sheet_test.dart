import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_pin.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/services/kotonoha_api_service.dart';
import 'package:kotonoha/widgets/kotonoha_candidate_sheet.dart';

/// [KotonohaCandidateSheet] fetches each candidate's own summary via
/// fetchKotonohaRootDetail — this fake lets each id resolve to its own
/// comment/date (or, for [failingIds], a thrown [KotonohaApiException]),
/// and can optionally hold every call open on [gate] until the test
/// completes it, to exercise the sheet's own loading state.
class _FakeApiService implements KotonohaApiService {
  _FakeApiService(this._byId, {this.failingIds = const {}, this.gate});

  final Map<String, ({String comment, String createdAt})> _byId;
  final Set<String> failingIds;
  final Completer<void>? gate;

  final List<int> requestedIds = [];

  @override
  Future<KotonohaRootDetail> fetchKotonohaRootDetail({
    required int id,
    double? latitude,
    double? longitude,
  }) async {
    requestedIds.add(id);
    if (gate != null) await gate!.future;

    final idString = id.toString();
    if (failingIds.contains(idString)) {
      throw KotonohaApiException(KotonohaApiFailureReason.server, 'failed');
    }
    final entry = _byId[idString]!;
    return KotonohaRootDetail(
      root: KotonohaRootSummary(
        id: idString,
        comment: entry.comment,
        createdAt: entry.createdAt,
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

/// Opens [KotonohaCandidateSheet] the same way KotonohaMap does
/// (`showModalBottomSheet<String>`), reporting whatever id (or null) it
/// resolves with via [onResult] — this is the only way to genuinely
/// observe the sheet's `Navigator.pop(context, id)` result from a test.
Widget _harness({
  required List<String> candidateIds,
  required KotonohaApiService apiService,
  required ValueChanged<String?> onResult,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => KotonohaCandidateSheet(
                  candidateIds: candidateIds,
                  apiService: apiService,
                ),
              );
              onResult(result);
            },
            child: const Text('open sheet'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a loading indicator before the candidates resolve', (
    tester,
  ) async {
    final gate = Completer<void>();
    final apiService = _FakeApiService({
      '10': (comment: '白い', createdAt: '2026-09-07T22:49:00+09:00'),
    }, gate: gate);

    await tester.pumpWidget(
      _harness(candidateIds: const ['10'], apiService: apiService, onResult: (_) {}),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet's own entrance animation

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('白い'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('白い'), findsOneWidget);
  });

  testWidgets(
    'shows the heading, and every candidate\'s comment and date/time',
    (tester) async {
      final apiService = _FakeApiService({
        '10': (comment: '白い', createdAt: '2026-09-07T22:49:00+09:00'),
        '11': (comment: '○○○', createdAt: '2026-09-08T18:21:00+09:00'),
      });

      await tester.pumpWidget(
        _harness(
          candidateIds: const ['10', '11'],
          apiService: apiService,
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('この場所の言の葉'), findsOneWidget);
      expect(find.text('白い'), findsOneWidget);
      expect(find.text('2026/09/07 22:49'), findsOneWidget);
      expect(find.text('○○○'), findsOneWidget);
      expect(find.text('2026/09/08 18:21'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the 1st candidate resolves with the 1st id — not an '
    'index-dependent guess',
    (tester) async {
      final apiService = _FakeApiService({
        '10': (comment: '白い', createdAt: '2026-09-07T22:49:00+09:00'),
        '11': (comment: '○○○', createdAt: '2026-09-08T18:21:00+09:00'),
      });
      String? result;

      await tester.pumpWidget(
        _harness(
          candidateIds: const ['10', '11'],
          apiService: apiService,
          onResult: (id) => result = id,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('白い'));
      await tester.pumpAndSettle();

      expect(result, '10');
    },
  );

  testWidgets(
    'tapping the 2nd candidate resolves with the 2nd id — not the 1st',
    (tester) async {
      final apiService = _FakeApiService({
        '10': (comment: '白い', createdAt: '2026-09-07T22:49:00+09:00'),
        '11': (comment: '○○○', createdAt: '2026-09-08T18:21:00+09:00'),
      });
      String? result;

      await tester.pumpWidget(
        _harness(
          candidateIds: const ['10', '11'],
          apiService: apiService,
          onResult: (id) => result = id,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('○○○'));
      await tester.pumpAndSettle();

      expect(result, '11');
    },
  );

  testWidgets(
    'a candidate whose own fetch fails still shows a fallback row that '
    'remains tappable, rather than breaking the whole sheet',
    (tester) async {
      final apiService = _FakeApiService(
        {'11': (comment: '○○○', createdAt: '2026-09-08T18:21:00+09:00')},
        failingIds: const {'10'},
      );
      String? result;

      await tester.pumpWidget(
        _harness(
          candidateIds: const ['10', '11'],
          apiService: apiService,
          onResult: (id) => result = id,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('読み込みに失敗しました'), findsOneWidget);
      expect(find.text('○○○'), findsOneWidget);

      await tester.tap(find.text('読み込みに失敗しました'));
      await tester.pumpAndSettle();

      expect(result, '10');
    },
  );

  testWidgets(
    'many candidates: the list scrolls internally rather than the sheet '
    'growing to hold them all at once',
    (tester) async {
      final byId = {
        for (var i = 0; i < 20; i++)
          '$i': (comment: '言の葉$i', createdAt: '2026-09-07T12:00:00+09:00'),
      };
      final apiService = _FakeApiService(byId);

      await tester.pumpWidget(
        _harness(
          candidateIds: [for (var i = 0; i < 20; i++) '$i'],
          apiService: apiService,
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      // The sheet caps its own height (see KotonohaCandidateSheet's
      // ConstrainedBox) rather than growing to fit 20 rows on screen at
      // once, so the last one isn't visible without scrolling yet.
      expect(find.text('言の葉0'), findsOneWidget);
      expect(find.text('言の葉19'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(find.text('言の葉19'), findsOneWidget);
    },
  );
}
