import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/widgets/kotonoha_leaf_popup.dart';
import 'package:kotonoha/widgets/leaf_shape.dart';
import 'package:kotonoha/widgets/loading_leaf.dart';

const _farRoot = KotonohaRootSummary(
  id: '6',
  comment: '今日は風が気持ちいい',
  createdAt: '2026-09-07T12:34:00+09:00',
);

const _nearRoot = KotonohaRootSummary(
  id: '6',
  comment: '今日は風が気持ちいい',
  createdAt: '2026-09-07T12:34:00+09:00',
  latitude: 35.0,
  longitude: 139.0,
  accuracy: 8.5,
  imageUrl: 'https://example.test/media/kotonoha/a.jpg',
);

const _connections = [
  KotonohaConnection(
    id: '10',
    parentId: '6',
    comment: '空がすごく青い',
    createdAt: '2026-09-07T12:40:00+09:00',
  ),
  KotonohaConnection(
    id: '11',
    parentId: '6',
    comment: 'またここに来たい',
    createdAt: '2026-09-07T12:45:00+09:00',
  ),
  KotonohaConnection(
    id: '12',
    parentId: '6',
    comment: '秋になったら来よう',
    createdAt: '2026-09-07T12:50:00+09:00',
  ),
  KotonohaConnection(
    id: '13',
    parentId: '6',
    comment: 'これは4件目',
    createdAt: '2026-09-07T12:55:00+09:00',
  ),
];

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets(
    'STEP13: the popup is always leaf-shaped (ClipPath + LeafClipper), '
    'never a photo, at every status',
    (tester) async {
      for (final status in KotonohaLeafPopupStatus.values) {
        await tester.pumpWidget(
          _wrap(
            KotonohaLeafPopup(
              status: status,
              root: status == KotonohaLeafPopupStatus.loaded ? _nearRoot : null,
              connectedItems: _connections,
              isNear: true,
              onDetail: () {},
              onRetry: () {},
            ),
          ),
        );

        expect(
          find.byWidgetPredicate((w) => w is ClipPath && w.clipper is LeafClipper),
          findsOneWidget,
          reason: 'status=$status should still render inside the leaf shape',
        );
        expect(find.byType(Image), findsNothing, reason: 'status=$status');
      }
    },
  );

  testWidgets(
    'STEP13: loading shows the animated LoadingLeaf, never a '
    'CircularProgressIndicator or "距離を確認しています" text',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.loading)),
      );

      expect(find.byType(LoadingLeaf), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('距離を確認'), findsNothing);
      expect(find.textContaining('確認しています'), findsNothing);

      // The animation is a Ticker-driven AnimationController; pump a few
      // frames and settle it explicitly rather than leaving it dangling.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('notFound shows the not-found message', (tester) async {
    await tester.pumpWidget(
      _wrap(const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.notFound)),
    );

    expect(find.text('この言の葉は見つかりませんでした'), findsOneWidget);
  });

  testWidgets('error shows the message and a working retry button', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        KotonohaLeafPopup(
          status: KotonohaLeafPopupStatus.error,
          errorMessage: '読み込みに失敗しました',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('読み込みに失敗しました'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    expect(retried, isTrue);
  });

  group('loaded, far (isNear: false) — 5m超: comment/date only', () {
    testWidgets('shows only the comment and date — no photo, no connected '
        'items, no "言の葉をひらく" button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _farRoot,
            isNear: false,
          ),
        ),
      );

      expect(find.text('今日は風が気持ちいい'), findsOneWidget);
      expect(find.text('2026/09/07 12:34'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('言の葉をひらく'), findsNothing);
      expect(find.text('詳細を見る'), findsNothing);
      expect(find.text('詳細'), findsNothing);
    });

    testWidgets('shows the location-unavailable note when given one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _farRoot,
            isNear: false,
            locationUnavailableMessage: '現在地を確認できないため、詳細を表示できません。',
          ),
        ),
      );

      expect(find.textContaining('現在地を確認できないため'), findsOneWidget);
    });
  });

  group('loaded, near (isNear: true) — 5m以内: comment/date/connections/'
      '「言の葉をひらく」, never a photo', () {
    testWidgets('shows connections (capped, "ほかN件") and an enabled '
        '「言の葉をひらく」 button — no photo anywhere', (tester) async {
      var detailTapped = false;
      await tester.pumpWidget(
        _wrap(
          KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            connectedItems: _connections,
            isNear: true,
            onDetail: () => detailTapped = true,
          ),
        ),
      );

      expect(find.text('今日は風が気持ちいい'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('空がすごく青い'), findsOneWidget);
      expect(find.text('またここに来たい'), findsOneWidget);
      expect(find.text('秋になったら来よう'), findsOneWidget);
      // Only the first 3 connected items are shown directly; the 4th is
      // summarized instead.
      expect(find.text('これは4件目'), findsNothing);
      expect(find.text('ほか1件'), findsOneWidget);

      expect(find.text('言の葉をひらく'), findsOneWidget);
      expect(find.text('詳細を見る'), findsNothing);
      await tester.tap(find.text('言の葉をひらく'));
      expect(detailTapped, isTrue);
    });

    testWidgets('with no connections, shows no divider/list and just the '
        '「言の葉をひらく」 button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            isNear: true,
          ),
        ),
      );

      expect(find.byType(Divider), findsNothing);
      expect(find.text('言の葉をひらく'), findsOneWidget);
    });
  });
}
