import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/widgets/kotonoha_leaf_popup.dart';
import 'package:kotonoha/widgets/leaf_shape.dart';
import 'package:kotonoha/widgets/loading_leaf.dart';

/// The popup's own dedicated leaf art (kotonoha_leaf_popup.dart's private
/// `_leafAsset` — duplicated here rather than exported, since only this
/// test needs to know the literal path).
const _popupLeafAsset = 'assets/design/leaf_popup.png';

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
    'image-asset pass: the popup renders its dedicated generated leaf '
    'artwork (leaf_popup.png) as its background for every status except '
    'loading (real-device UI pass: loading gets its own leaf_popup.png-'
    'free subtree — see the loading-specific group below), and the Root '
    'photo (imageUrl) is never rendered at any status',
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
        // AnimatedSwitcher's own transition needs a settle before the
        // steady-state tree (no leftover outgoing child) can be asserted.
        await tester.pumpAndSettle();

        final leafArtworkFinder = find.byWidgetPredicate(
          (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == _popupLeafAsset,
        );
        if (status == KotonohaLeafPopupStatus.loading) {
          expect(leafArtworkFinder, findsNothing, reason: 'status=$status');
        } else {
          expect(
            leafArtworkFinder,
            findsOneWidget,
            reason: 'status=$status should render the leaf artwork as its background',
          );
        }
        // The Root's own photo (root.imageUrl) must never be rendered
        // here (docs section 8) — distinct from the leaf artwork itself,
        // which legitimately is an Image now (image-asset pass).
        expect(
          find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
          findsNothing,
          reason: 'status=$status',
        );
      }
    },
  );

  group('real-device UI pass: loading never shows the leaf_popup.png '
      'window (only the small animated loading leaf), and the two never '
      'coexist', () {
    testWidgets('loading shows only the small LoadingLeaf — no '
        'leaf_popup.png, no date/comment/button', (tester) async {
      await tester.pumpWidget(
        _wrap(const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.loading)),
      );

      expect(find.byType(LoadingLeaf), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == _popupLeafAsset,
        ),
        findsNothing,
      );
      expect(find.text('言の葉をひらく'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('once loaded, the leaf_popup.png window appears and the '
        'loading leaf is gone (after the transition settles) — they are '
        'never both present', (tester) async {
      await tester.pumpWidget(
        _wrap(const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.loading)),
      );
      expect(find.byType(LoadingLeaf), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            isNear: true,
            onDetail: () {},
          ),
        ),
      );
      // Let the AnimatedSwitcher's cross-fade fully finish.
      await tester.pumpAndSettle();

      expect(find.byType(LoadingLeaf), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == _popupLeafAsset,
        ),
        findsOneWidget,
      );
      expect(find.text('言の葉をひらく'), findsOneWidget);
    });
  });

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
      // No photo — distinct from the leaf artwork itself, which is
      // legitimately an Image now (image-asset pass).
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
        findsNothing,
      );
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
      // No photo — distinct from the leaf artwork itself, which is
      // legitimately an Image now (image-asset pass).
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
        findsNothing,
      );
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

    testWidgets(
      'STEP13 UI fix: a long comment plus 4 connections never overflows '
      'the leaf (no RenderFlex/layout overflow), and 「言の葉をひらく」 '
      'still renders — regression test for the leaf outline clipping '
      'content once the popup grew tall',
      (tester) async {
        final longRoot = KotonohaRootSummary(
          id: '99',
          comment: 'そ' * 50,
          createdAt: '2026-09-07T12:34:00+09:00',
          latitude: 35.0,
          longitude: 139.0,
          accuracy: 8.5,
        );

        await tester.pumpWidget(
          _wrap(
            KotonohaLeafPopup(
              status: KotonohaLeafPopupStatus.loaded,
              root: longRoot,
              connectedItems: _connections,
              isNear: true,
              onDetail: () {},
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('言の葉をひらく'), findsOneWidget);
        expect(find.text('ほか1件'), findsOneWidget);
      },
    );
  });

  group('STEP14: a tap inside the leaf silhouette is absorbed, never '
      'reaching a layer stacked underneath it', () {
    // Mirrors the z-order KotonohaMap actually uses while a popup is open
    // (STEP14 section 11): a full-size tap-to-close layer underneath, the
    // leaf popup on top of it. KotonohaMap itself can't be exercised here
    // (GoogleMap is a platform view — see kotonoha_map_test.dart), so this
    // isolates the one piece of that interaction that doesn't depend on
    // it: whether KotonohaLeafPopup's own hit-testing actually shields the
    // layer beneath it.
    Widget wrapInMapLikeStack(Widget popup, {required VoidCallback onClose}) =>
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                  ),
                ),
                Center(child: popup),
              ],
            ),
          ),
        );

    testWidgets('tapping 「言の葉をひらく」 opens detail and does not also '
        'trigger the closer underneath', (tester) async {
      var detailTapped = false;
      var closerTapped = false;
      await tester.pumpWidget(
        wrapInMapLikeStack(
          KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            isNear: true,
            onDetail: () => detailTapped = true,
          ),
          onClose: () => closerTapped = true,
        ),
      );

      await tester.tap(find.text('言の葉をひらく'));
      expect(detailTapped, isTrue);
      expect(closerTapped, isFalse);
    });

    testWidgets('tapping the comment text (inside the leaf, away from any '
        'button) is absorbed by the leaf — the closer underneath does not '
        'fire', (tester) async {
      var closerTapped = false;
      await tester.pumpWidget(
        wrapInMapLikeStack(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            isNear: true,
          ),
          onClose: () => closerTapped = true,
        ),
      );

      await tester.tap(find.text('今日は風が気持ちいい'));
      expect(closerTapped, isFalse);
    });

    testWidgets('tapping well outside the popup (e.g. near the screen '
        'corner) reaches the closer underneath — confirms the stack setup '
        'above genuinely lets outside taps through', (tester) async {
      var closerTapped = false;
      await tester.pumpWidget(
        wrapInMapLikeStack(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: _nearRoot,
            isNear: true,
          ),
          onClose: () => closerTapped = true,
        ),
      );

      await tester.tapAt(const Offset(5, 5));
      expect(closerTapped, isTrue);
    });
  });

  group('real-device UI pass: 50-character comments (KOTONOHA\'s own '
      'posting limit) always render in full, never ellipsized', () {
    // A worst-case 50-character string: a single repeated wide character,
    // with no punctuation to give the layout an easy line-break point.
    final fiftyCharComment = 'あ' * 50;

    testWidgets('a 50-character comment (far, isNear: false) renders in '
        'full with no overflow and no "…"', (tester) async {
      expect(fiftyCharComment.length, 50);
      final root = KotonohaRootSummary(
        id: '50',
        comment: fiftyCharComment,
        createdAt: '2026-09-07T22:49:00+09:00',
      );

      await tester.pumpWidget(
        _wrap(
          KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: root,
            isNear: false,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(fiftyCharComment), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('a 50-character comment (near, isNear: true, with '
        'connections) renders in full, with no overflow, and '
        '「言の葉をひらく」 still renders', (tester) async {
      expect(fiftyCharComment.length, 50);
      final root = KotonohaRootSummary(
        id: '50',
        comment: fiftyCharComment,
        createdAt: '2026-09-07T22:49:00+09:00',
        latitude: 35.0,
        longitude: 139.0,
        accuracy: 8.5,
      );

      await tester.pumpWidget(
        _wrap(
          KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: root,
            connectedItems: _connections,
            isNear: true,
            onDetail: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(fiftyCharComment), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
      expect(find.text('言の葉をひらく'), findsOneWidget);
    });

    testWidgets('a short comment still renders in full, unaffected by the '
        'auto-sizing added for the 50-character case', (tester) async {
      const root = KotonohaRootSummary(
        id: '1',
        comment: 'いいね',
        createdAt: '2026-09-07T22:49:00+09:00',
      );

      await tester.pumpWidget(
        _wrap(
          const KotonohaLeafPopup(
            status: KotonohaLeafPopupStatus.loaded,
            root: root,
            isNear: false,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('いいね'), findsOneWidget);
    });
  });

  group('leaf silhouette (buildLeafPath)', () {
    test('stays within its own bounds and closes back to the tip at every '
        'size — including sizes shorter than the combined cap fractions '
        '(e.g. a small LoadingLeaf), which must not go negative', () {
      for (final size in const [
        Size(280, 460), // a tall, content-heavy popup
        Size(280, 300), // a short popup (little content)
        Size(52, 70), // the map marker's body
        Size(40, 52), // LoadingLeaf's default size
        Size(10, 10), // pathological: shorter than top+bottom caps
      ]) {
        final path = buildLeafPath(size);
        final bounds = path.getBounds();

        expect(bounds.left, greaterThanOrEqualTo(-0.01));
        expect(bounds.top, greaterThanOrEqualTo(-0.01));
        expect(bounds.right, lessThanOrEqualTo(size.width + 0.01));
        expect(bounds.bottom, lessThanOrEqualTo(size.height + 0.01));
      }
    });

    test('LeafClipper never reclips (shouldReclip is always false)', () {
      const clipper = LeafClipper();
      expect(
        clipper.shouldReclip(const LeafClipper()),
        isFalse,
      );
    });
  });
}
