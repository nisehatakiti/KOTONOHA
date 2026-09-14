import 'package:flutter/material.dart';

import '../models/kotonoha_root_detail.dart';
import '../utils/kotonoha_format.dart';
import 'loading_leaf.dart';

/// What to render inside [KotonohaLeafPopup] (STEP11-UI): a pure
/// presentation state — all the fetching/distance logic that decides
/// which of these applies lives in HomeScreen, never in this widget.
enum KotonohaLeafPopupStatus { loading, notFound, error, loaded }

/// The "opened leaf" shown near a tapped leaf marker (STEP13,
/// docs/map-ui-spec.md section 6) — the small marker itself is hidden by
/// [KotonohaMap] while this is visible (section 6.1), so this widget's own
/// visual has to read as "that same leaf, opened up" rather than a
/// separate speech-bubble window.
///
/// Content is gated by [isNear] (5m rule, docs section 7): far away, only
/// the Root post's comment and date are shown — no connected comments, no
/// "言の葉をひらく" button at all (not just disabled). Within 5m, the
/// connected comments and the button appear. Photos are never shown here
/// at any distance (section 8) — only [KotonohaDetailScreen], reached via
/// that button, shows the Root's photo.
///
/// This widget never talks to the network itself (HomeScreen/API Service
/// do) and never navigates anywhere itself — [onDetail] is a plain
/// callback the caller wires to whatever navigation it wants.
///
/// Image-asset pass: the leaf itself — shape, color, veins, stem — used
/// to be drawn in code (a generated [Path] filled/stroked by a
/// [CustomPainter], clipped with [ClipPath]). It is now
/// `assets/design/leaf_popup.png` displayed with a plain [Image.asset] as
/// this [Stack]'s background layer, with the dynamic comment/date/
/// connections/button positioned on top of it — no [CustomPainter], no
/// [Path], no [ClipPath] anywhere in this file.
///
/// A previous pass reused the map marker's own artwork
/// (leaf_marker_icon.dart) here too, enlarged, because it was the only
/// leaf-only, sample-text-free art available at the time. This asset is
/// now a *dedicated* popup generation — its own, wider silhouette (not
/// the marker's narrower one, and not the earlier design sheet's
/// "ポップアップ" mockup cells, which had sample text baked into their
/// pixels) — so [_width]/[_height] and the padding fractions below are
/// specific to it. Its source export had its transparency baked in as a
/// checkerboard placeholder rather than a real alpha channel (a common
/// artifact of some image-generation exports); that was corrected by
/// chroma-keying the checkerboard's two near-neutral tones back to real
/// alpha (`assets/design/leaf_popup.png`'s current pixels) — a mechanical,
/// pixel-level export fix that never touched the leaf's own color/shape/
/// texture, not a redraw.
///
/// See [_topPaddingFraction]/[_bottomPaddingFraction]/
/// [_sidePaddingFraction] for how the content area is positioned within
/// it, measured from the asset's own actual pixel silhouette (not
/// guessed) so text stays clear of the tapered tip and stem base.
class KotonohaLeafPopup extends StatelessWidget {
  const KotonohaLeafPopup({
    super.key,
    required this.status,
    this.root,
    this.connectedItems = const [],
    this.isNear = false,
    this.locationUnavailableMessage,
    this.errorMessage,
    this.onRetry,
    this.onDetail,
  });

  final KotonohaLeafPopupStatus status;

  /// The tapped Root post, exactly as the server returned it. Only
  /// meaningful when [status] is `loaded`. Its `imageUrl` is intentionally
  /// never rendered here (docs section 8) — only kept on the model for
  /// [KotonohaDetailScreen] to use.
  final KotonohaRootSummary? root;

  /// The Root's own connect posts, straight from `response.connections`
  /// (STEP11-UI (B) fix: server-side parent_id filtering — never a
  /// client-side spatial guess). Only rendered when [isNear] is true, as
  /// words strung on below the Root's own (docs section 6: 「その場所に
  /// 置かれたRoot投稿と、それに繋がれた言葉の束」).
  final List<KotonohaConnection> connectedItems;

  /// Whether the user is within 5m of [root] — gates the connected-
  /// comments list and the "言の葉をひらく" button (docs section 7).
  /// Defaults to false (far/unknown), matching "安全側に倒す" for the
  /// case where distance couldn't be determined.
  final bool isNear;

  /// Set when the current location couldn't be read at all — shown as an
  /// extra note under the Root comment/date, which are still visible
  /// either way.
  final String? locationUnavailableMessage;

  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onDetail;

  static const _maxConnectedPreview = 3;

  /// The dedicated popup leaf art — a separate generation from the map
  /// marker's (leaf_marker_icon.dart), not a crop or reuse of it.
  static const String _leafAsset = 'assets/design/leaf_popup.png';

  // _leafAsset's own pixel size, exactly as cropped (tight bounding box,
  // a few px of margin) — used to derive [_height] from [_width] without
  // distortion, and nothing else.
  static const double _leafAssetNativeWidth = 730;
  static const double _leafAssetNativeHeight = 1132;

  // The displayed size of _leafAsset — width is chosen for what reads as
  // natural on a phone screen, height is derived from the asset's own
  // native pixel ratio so Image.asset (fit: BoxFit.contain, itself a pure
  // scale — no stretching) never distorts it (「縦横比・葉っぱの形…を変更
  // してはいけない」). No longer tied to the map marker's own size/shape —
  // this is its own dedicated popup art, sized for what a KOTONOHA leaf
  // popup actually needs to hold.
  static const double _width = 280;
  static const double _height = _width * _leafAssetNativeHeight / _leafAssetNativeWidth;

  // Where the actual leaf blade is comfortably wide, as fractions of
  // [_width]/[_height] — measured directly off _leafAsset's own pixels
  // (the per-row width of its non-transparent silhouette), not guessed:
  // this art's blade is close to its widest between roughly 24%–77% of
  // its height (much more generous than the marker's own narrower
  // silhouette), narrowing sharply above that (the tip) and below it (the
  // waist into the stem). These fractions keep the content comfortably
  // inside that band rather than drifting into either taper.
  //
  // Real-device fix: [_topPaddingFraction] is slightly larger than
  // [_bottomPaddingFraction] (rather than the reverse, which the safe-
  // band numbers alone would suggest) — on-device this content read as
  // sitting too high, leaving a large gap of bare leaf below it and
  // almost none above. Shifting the zone itself down a little, combined
  // with actually centering content *within* that zone (see [build] —
  // short content, like the 5m超 comment+date-only case, no longer sits
  // pinned to the zone's own top edge), is what moves it down.
  static const double _sidePaddingFraction = 0.17;
  static const double _topPaddingFraction = 0.28;
  static const double _bottomPaddingFraction = 0.22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: GestureDetector(
        // Absorbs any tap within the popup's own box — including its
        // image's transparent corners, a minor trade-off of no longer
        // clipping to the leaf's exact silhouette — so it never falls
        // through to KotonohaMap's STEP14 tap-to-close layer underneath
        // (docs STEP14 section 11: 「ウィンドウ内部をタップしても閉じな
        // い」). See kotonoha_map.dart for that layer.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Stack(
          children: [
            // The leaf itself — shape, color, veins, stem, all baked into
            // the PNG. BoxFit.contain only ever scales this uniformly; it
            // never stretches or redraws it.
            Positioned.fill(
              child: Image.asset(_leafAsset, fit: BoxFit.contain),
            ),
            Positioned(
              left: _width * _sidePaddingFraction,
              right: _width * _sidePaddingFraction,
              top: _height * _topPaddingFraction,
              bottom: _height * _bottomPaddingFraction,
              // Real-device fix: a SingleChildScrollView always fills the
              // full padded zone regardless of how much content it holds,
              // and by default lays that content out flush against its
              // own top — so short content (e.g. the 5m超 comment+date-
              // only case) was ending up pinned to the *top* of the zone,
              // reading as "too high" even though the zone itself already
              // left headroom above it. LayoutBuilder + a minHeight
              // ConstrainedBox + Center make short content sit centered
              // in the zone instead, while content long enough to need it
              // still scrolls exactly as before.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(child: _buildContent(context)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (status) {
      case KotonohaLeafPopupStatus.loading:
        return const Center(child: LoadingLeaf());

      case KotonohaLeafPopupStatus.notFound:
        return const Center(
          child: Text(
            'この言の葉は見つかりませんでした',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        );

      case KotonohaLeafPopupStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage ?? '読み込みに失敗しました',
              style: const TextStyle(fontSize: 12),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRetry, child: const Text('再試行')),
              ),
            ],
          ],
        );

      case KotonohaLeafPopupStatus.loaded:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final root = this.root;
    if (root == null) {
      // Shouldn't normally happen (HomeScreen maps a missing root to
      // notFound), but never crash on it either way.
      return const Text(
        'この言の葉は見つかりませんでした',
        style: TextStyle(fontSize: 12),
      );
    }

    final children = <Widget>[
      Text(
        root.comment,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        // Near-black and explicit rather than an inherited default — the
        // confirmed spec calls for readable, black-toned text over the
        // leaf's pale-to-mid green.
        style: const TextStyle(fontSize: 13, height: 1.3, color: Colors.black87),
      ),
      const SizedBox(height: 6),
      Text(
        formatKotonohaDateTime(root.createdAt),
        style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
      ),
    ];

    if (!isNear) {
      if (locationUnavailableMessage != null) {
        children.addAll([
          const SizedBox(height: 6),
          Text(
            locationUnavailableMessage!,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
          ),
        ]);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    if (connectedItems.isNotEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1),
      ));
      final preview = connectedItems.take(_maxConnectedPreview);
      for (final item in preview) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              item.comment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        );
      }
      final remaining = connectedItems.length - _maxConnectedPreview;
      if (remaining > 0) {
        children.add(
          Text('ほか$remaining件', style: TextStyle(fontSize: 10, color: Colors.grey.shade800)),
        );
      }
    }

    children.addAll([
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onDetail,
          child: const Text('言の葉をひらく'),
        ),
      ),
    ]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
