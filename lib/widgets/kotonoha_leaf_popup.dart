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
/// pixels) — so [_width]/[_height] and the layout fractions below are
/// specific to it.
///
/// Real-device UI pass (latest): rather than one flowing text column
/// centered in a single padded zone, the date, the comment and the
/// "言の葉をひらく" button are now each their own [Positioned] region,
/// placed to match specific features of [_leafAsset]'s own artwork —
/// the date sits in the open space near the tip, the comment fills the
/// blade's wide midsection, and the button sits lower-left, near where
/// the leaf's own veins branch a second time from the bottom — all
/// measured from the asset's actual pixel silhouette/vein layout (see
/// each field's own doc comment for the specific evidence), not guessed.
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
  // してはいけない」). This is its own dedicated popup art, sized for what
  // a KOTONOHA leaf popup actually needs to hold.
  static const double _width = 280;
  static const double _height = _width * _leafAssetNativeHeight / _leafAssetNativeWidth;

  // --- Fallback zone (loading/notFound/error/loaded-with-no-root) -------
  // The single centered zone used for every status *except* a fully
  // loaded Root — same "wide band, measured off the asset's own pixel
  // silhouette" reasoning as the comment zone below, just simpler since
  // there's no date/button to place separately for these states.
  static const double _fallbackSidePaddingFraction = 0.17;
  static const double _fallbackTopFraction = 0.28;
  static const double _fallbackBottomFraction = 0.22;

  // --- Loaded-with-root layout -------------------------------------------
  //
  // Real-device fix: the date/time used to sit directly above the
  // comment, both packed into one zone — on-device this read as
  // cluttered, with the date barely distinguishable from the comment
  // above it. It now gets its own dedicated spot in the open space near
  // the leaf's tip, well clear of the comment below.
  //
  // Measured off _leafAsset's own per-row pixel width (the same
  // profiling method used to size the fallback zone / STEP13's original
  // safe-zone work): by ~15% of the image's height the blade is already
  // roughly a third of its full width, comfortably wide enough for a
  // short date string once centered.
  static const double _dateTopFraction = 0.155;

  // The comment's own zone: positioned to start clearly below the date
  // and end well above the button, inside the blade's widest band
  // (per the same per-row measurement, the blade stays at least ~60% of
  // its max width across this whole span). Side padding is a bit
  // narrower than the fallback zone's, since this band sits closer to
  // the blade's widest point.
  static const double _commentSidePaddingFraction = 0.18;
  static const double _commentTopFraction = 0.24;
  static const double _commentBottomFraction = 0.30;

  /// "言の葉をひらく": positioned lower-left, near where the leaf's own
  /// side veins branch off the midrib for the *second* time counting up
  /// from the base (visually counted off leaf_popup.png: the vein pairs
  /// sit at roughly even intervals down the blade, and the second pair
  /// up from where the blade narrows into the stem falls at around this
  /// fraction of the image's total height) — clearly below the comment
  /// zone above it, and clear of the stem, which only begins much lower
  /// (per the same profiling, the blade is still a majority of its max
  /// width here; it doesn't narrow into the stem until past 85%).
  static const double _buttonTopFraction = 0.73;

  /// Nudges the button a little right of [_buildOpenButton]'s previous
  /// position (real-device fix: moved right by roughly half a character's
  /// width from the prior `-0.16`), while still keeping its "を" — the
  /// 4th of the button's 7 characters, i.e. already almost exactly the
  /// middle of its own text — close to the leaf's true horizontal center
  /// (docs: 「「を」の文字が...横方向の中心に来る位置」「葉っぱの左下寄
  /// り」): this button's own rendered center still tracks "を"'s
  /// position closely, so this alignment value moves both together.
  static const Alignment _buttonAlignment = Alignment(-0.06, 0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Absorbs any tap within the popup's own box — including its
      // image's transparent corners, a minor trade-off of no longer
      // clipping to the leaf's exact silhouette — so it never falls
      // through to KotonohaMap's STEP14 tap-to-close layer underneath
      // (docs STEP14 section 11: 「ウィンドウ内部をタップしても閉じな
      // い」). See kotonoha_map.dart for that layer. Wraps the
      // AnimatedSwitcher below (not just the loaded body) so this covers
      // the loading phase too.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      // Real-device UI pass: the loading leaf and the finished leaf_popup
      // window used to be visible at the same time — a small
      // [LoadingLeaf] centered *inside* the already-fully-sized
      // leaf_popup.png background, from the very first tap. That's
      // exactly what docs section ⑥/⑧ call out as unwanted (「読み込み中
      // の葉っぱ」と「葉っぱウィンドウ」が同時に表示される状態は禁止」).
      // [status] now picks between two entirely separate subtrees —
      // [_buildLoadingLeaf] (just the small animated loading leaf, no
      // leaf_popup.png at all) and [_buildLeafBody] (the real
      // leaf_popup.png window, for every other status) — and
      // [AnimatedSwitcher] cross-fades/scales between them so the loading
      // leaf reads as opening into the popup rather than one abruptly
      // replacing the other.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.55, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: status == KotonohaLeafPopupStatus.loading
            ? _buildLoadingLeaf()
            : _buildLeafBody(context),
      ),
    );
  }

  /// The loading phase's entire visual — just the small animated
  /// [LoadingLeaf] (cycling leaf_loading_1/2/3.png), deliberately with no
  /// leaf_popup.png background and none of the popup's own content
  /// (date/comment/button) anywhere in this subtree, so there is no way
  /// for the finished popup and the loading indicator to be on screen
  /// together (docs section ⑥/⑧). Keyed so [AnimatedSwitcher] treats it
  /// as a distinct subtree from [_buildLeafBody].
  Widget _buildLoadingLeaf() {
    return const KeyedSubtree(
      key: ValueKey('leaf-popup-loading'),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Center(child: LoadingLeaf(height: 68)),
      ),
    );
  }

  /// The real leaf_popup.png window — used for every status except
  /// [KotonohaLeafPopupStatus.loading] (notFound/error use
  /// [_buildFallbackZone]'s simple centered message; a fully loaded Root
  /// uses the date/comment/button split layout). This is exactly what
  /// [build] used to return unconditionally before the loading phase got
  /// its own separate, leaf_popup.png-free subtree.
  Widget _buildLeafBody(BuildContext context) {
    final showSplitLayout = status == KotonohaLeafPopupStatus.loaded && root != null;

    return KeyedSubtree(
      key: const ValueKey('leaf-popup-body'),
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          children: [
            // The leaf itself — shape, color, veins, stem, all baked into
            // the PNG. BoxFit.contain only ever scales this uniformly; it
            // never stretches or redraws it.
            Positioned.fill(
              child: Image.asset(_leafAsset, fit: BoxFit.contain),
            ),
            if (showSplitLayout) ...[
              _buildDate(),
              _buildCommentZone(),
              if (isNear) _buildOpenButton(),
            ] else
              _buildFallbackZone(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDate() {
    return Positioned(
      top: _height * _dateTopFraction,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          formatKotonohaDateTime(root!.createdAt),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _buildCommentZone() {
    return Positioned(
      left: _width * _commentSidePaddingFraction,
      right: _width * _commentSidePaddingFraction,
      top: _height * _commentTopFraction,
      bottom: _height * _commentBottomFraction,
      // A safety net, not the primary sizing mechanism: the comment
      // itself is guaranteed to fit its own budget (see
      // _AutoSizeBoldComment), but connected items below it are not
      // auto-sized, so unexpectedly long content there still scrolls
      // instead of running past the leaf artwork's own edge.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The comment gets a fixed share of this zone's height as its
          // own sizing budget — not the zone's full height — so it never
          // crowds out room for connected items below it even when the
          // zone itself has to grow to keep a 50-character comment from
          // ever needing to shrink past a readable size.
          final commentBudgetHeight = constraints.maxHeight * 0.62;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AutoSizeBoldComment(
                      text: root!.comment,
                      maxWidth: constraints.maxWidth,
                      maxHeight: commentBudgetHeight,
                    ),
                    if (isNear)
                      ..._buildConnectedItems()
                    else if (locationUnavailableMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        locationUnavailableMessage!,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildConnectedItems() {
    if (connectedItems.isEmpty) return const [];

    final widgets = <Widget>[
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1),
      ),
    ];
    final preview = connectedItems.take(_maxConnectedPreview);
    for (final item in preview) {
      widgets.add(
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
      widgets.add(
        Text('ほか$remaining件', style: TextStyle(fontSize: 10, color: Colors.grey.shade800)),
      );
    }
    return widgets;
  }

  Widget _buildOpenButton() {
    return Positioned(
      top: _height * _buttonTopFraction,
      left: 0,
      right: 0,
      child: Align(
        alignment: _buttonAlignment,
        // Real-device fix: a plain TextButton (text only, no fill/border)
        // read as barely-there against the leaf's own green — switched to
        // a small white, rounded-rectangle button so it's unmistakably a
        // tappable control sitting on top of the leaf. onPressed/onDetail
        // and where it navigates are unchanged; only the button's own
        // paint style is new.
        child: ElevatedButton(
          onPressed: onDetail,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF3F7D33),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 2,
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: const Text('言の葉をひらく'),
        ),
      ),
    );
  }

  Widget _buildFallbackZone(BuildContext context) {
    return Positioned(
      left: _width * _fallbackSidePaddingFraction,
      right: _width * _fallbackSidePaddingFraction,
      top: _height * _fallbackTopFraction,
      bottom: _height * _fallbackBottomFraction,
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
        // Only reached when root == null (build()'s showSplitLayout
        // already routes the normal loaded+root case elsewhere) —
        // shouldn't normally happen (HomeScreen maps a missing root to
        // notFound), but never crash on it either way.
        return const Text(
          'この言の葉は見つかりませんでした',
          style: TextStyle(fontSize: 12),
        );
    }
  }
}

/// A bold [Text] that picks the largest font size (within
/// [_maxFontSize]/[_minFontSize]) whose *wrapped* layout still fits
/// within [maxWidth]/[maxHeight] — it never ellipsizes and never drops
/// characters. Exists specifically so a 50-character comment (KOTONOHA's
/// own posting limit) always renders in full inside the leaf's comment
/// zone: 「文字を大きくすることより、最大50文字の全文を表示できることを
/// 優先」, so this shrinks in small steps until the *whole* string —
/// however it naturally wraps at [maxWidth] — is short enough to fit
/// [maxHeight], rather than ever truncating it.
class _AutoSizeBoldComment extends StatelessWidget {
  const _AutoSizeBoldComment({
    required this.text,
    required this.maxWidth,
    required this.maxHeight,
  });

  final String text;
  final double maxWidth;
  final double maxHeight;

  static const double _maxFontSize = 16;
  static const double _minFontSize = 9;
  static const double _step = 0.5;
  static const double _lineHeight = 1.28;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: _fittingFontSize(),
        fontWeight: FontWeight.bold,
        height: _lineHeight,
        color: Colors.black87,
      ),
      softWrap: true,
      // Deliberately no maxLines/overflow — the whole point is to never
      // ellipsize; _fittingFontSize already guarantees the full text fits
      // maxHeight at the size it returns.
    );
  }

  /// The largest size in [_maxFontSize]..[_minFontSize] (falling back to
  /// [_minFontSize] itself if even that doesn't fit — still the full
  /// text, just as small as this widget is willing to go) whose wrapped
  /// layout at [maxWidth] fits within [maxHeight].
  double _fittingFontSize() {
    if (maxWidth <= 0 || maxHeight <= 0) return _minFontSize;
    for (double size = _maxFontSize; size > _minFontSize; size -= _step) {
      if (_fits(size)) return size;
    }
    return _minFontSize;
  }

  bool _fits(double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, height: _lineHeight),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.size.height <= maxHeight;
  }
}
