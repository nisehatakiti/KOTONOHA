import 'package:flutter/widgets.dart';

/// UNUSED as of the image-asset pass — kept in place rather than deleted
/// (nothing in lib/ imports this file anymore; verified via
/// `grep -rl leaf_shape lib/`), since removing it wasn't asked for this
/// pass and the file itself does no harm sitting idle. STEP13/14 built
/// KOTONOHA's leaf UI as a generated [Path] ([buildLeafPath]) filled by a
/// [CustomPainter] and clipped with [ClipPath] ([LeafClipper]) — the map
/// marker (leaf_marker_icon.dart), the expanded popup
/// (kotonoha_leaf_popup.dart) and the loading indicator (loading_leaf.dart)
/// all drew a leaf shape in code this way.
///
/// A later pass replaced all three with a generated PNG
/// (assets/design/leaf_marker.png etc., cropped from
/// assets/design/a_clean_design_asset_sheet_on_a_transparent_checke.png)
/// displayed via [Image.asset] instead — see those three files' own doc
/// comments. None of them reference [buildLeafPath]/[LeafClipper]/
/// [LeafCapFractions] anymore. This file's own unit tests
/// (test/kotonoha_leaf_popup_test.dart, "leaf silhouette (buildLeafPath)")
/// still exercise it directly and still pass, since the functions
/// themselves are unchanged — only their earlier callers stopped using
/// them.
///
/// How much of a leaf's *width* is given to the tapered tip (top) and the
/// tapered base/stem-waist (bottom) in [buildLeafPath] — the wide "belly"
/// in between gets whatever height is left over.
///
/// These are fractions of width, not of the total height, on purpose
/// (STEP13 visual fix, see [buildLeafPath] for why): it's what keeps the
/// caps looking like a consistent leaf tip/base no matter how tall the
/// popup grows to fit its content, and it's what
/// [KotonohaLeafPopup]'s content padding is derived from, so text never
/// drifts into the tapered zone the way it did before this fix.
class LeafCapFractions {
  const LeafCapFractions._();

  /// The tip, top of the leaf.
  static const double top = 0.38;

  /// The base/waist leading into the stem — slightly larger than [top] so
  /// it reads as a distinct "this is where the stem attaches" narrowing
  /// rather than a mirror image of the tip.
  static const double bottom = 0.44;
}

/// The leaf silhouette shared by every leaf surface in KOTONOHA (STEP13)
/// — the small map marker ([leaf_marker_icon.dart]), the expanded leaf
/// popup ([KotonohaLeafPopup]), and [LoadingLeaf] all draw this same
/// shape at different sizes, so a tap reads as "the same leaf getting
/// bigger" rather than a switch to an unrelated shape (docs/map-ui-spec.md
/// section 6.2: 「葉っぱのシルエットを維持する」).
///
/// Redesigned after real-device testing of the original single-curve
/// almond (a smooth point-to-point lens: pointed top, pointed bottom,
/// widest at the dead center) — at small marker size it read fine, but
/// stretched tall for the expanded popup it looked like an oversized
/// water drop or a scaled-up map pin, and its widest point sat at a
/// *fraction* of the total height, so on a tall popup (lots of connected
/// comments) the tapered top/bottom crept much further into the frame
/// than a fixed content padding accounted for — clipping the comment,
/// date and "言の葉をひらく" button against the leaf's own outline.
///
/// This version draws the tapered tip and base as caps sized off the
/// shape's *width* (see [LeafCapFractions]) rather than its height, with
/// a near-vertical, gently bowed "belly" stretched in between to whatever
/// height is left over. A tall popup just grows a taller belly — the caps
/// (and the safe content zone between them) stay the same proportions
/// either way, which is also what makes it possible for
/// [KotonohaLeafPopup] to size its content padding once, from its own cap
/// fractions, instead of guessing at the final height.
///
/// [capTopFraction]/[capBottomFraction] default to [LeafCapFractions] —
/// the proportions tuned for the small map marker — but STEP14 gave the
/// expanded popup its own, much smaller fractions (see
/// [KotonohaLeafPopup]): the marker's tall caps read fine on a ~50px
/// glyph, but on the popup they alone produced a leaf taller than most of
/// its actual content, which is what made STEP13's "fixed" popup still
/// look like an oversized teardrop panel on a real device. Overriding the
/// fractions here — rather than changing [LeafCapFractions] itself — is
/// what lets the marker and the popup each use a cap proportion that
/// actually suits their own size, while still sharing this one curve
/// formula (docs STEP14 section 12/STEP13 section 12: 共通Pathを使うこと
/// 自体が目的ではない).
Path buildLeafPath(
  Size size, {
  double capTopFraction = LeafCapFractions.top,
  double capBottomFraction = LeafCapFractions.bottom,
}) {
  final width = size.width;
  final height = size.height;
  final centerX = width / 2;

  // Guard against a box shorter than both caps combined (e.g. a tiny
  // LoadingLeaf) by shrinking them proportionally rather than letting the
  // belly go negative.
  var capTop = width * capTopFraction;
  var capBottom = width * capBottomFraction;
  final capSum = capTop + capBottom;
  if (capSum > height) {
    final scale = height / capSum;
    capTop *= scale;
    capBottom *= scale;
  }

  final bellyTop = capTop;
  final bellyBottom = height - capBottom;
  final bellyMid = (bellyTop + bellyBottom) / 2;

  return Path()
    ..moveTo(centerX, 0)
    // Right shoulder: the tip curves out to the belly's right edge. A
    // slower bulge than the old shape's (which ballooned to ~full width
    // by 16% of the *height*) — this reads as a leaf tip narrowing
    // outward, not a balloon inflating.
    ..cubicTo(
      width * 0.74,
      capTop * 0.16,
      width * 0.97,
      capTop * 0.62,
      width * 0.90,
      bellyTop,
    )
    // Right belly: a gentle outward bow rather than a dead-straight
    // edge, so it still reads as an organic leaf blade once stretched
    // tall for a lot of content.
    ..quadraticBezierTo(width * 0.94, bellyMid, width * 0.90, bellyBottom)
    // Right base: belly narrows through the waist into the stem-base
    // point at the very bottom center.
    ..cubicTo(
      width * 0.86,
      bellyBottom + capBottom * 0.4,
      width * 0.64,
      height - capBottom * 0.06,
      centerX,
      height,
    )
    // Left base (mirrored).
    ..cubicTo(
      width * 0.36,
      height - capBottom * 0.06,
      width * 0.14,
      bellyBottom + capBottom * 0.4,
      width * 0.10,
      bellyBottom,
    )
    // Left belly (mirrored).
    ..quadraticBezierTo(width * 0.06, bellyMid, width * 0.10, bellyTop)
    // Left shoulder back to the tip (mirrored).
    ..cubicTo(
      width * 0.03,
      capTop * 0.62,
      width * 0.26,
      capTop * 0.16,
      centerX,
      0,
    )
    ..close();
}

/// Clips a widget to [buildLeafPath], sized to whatever the child actually
/// lays out as. [capTopFraction]/[capBottomFraction] let a caller (e.g.
/// [KotonohaLeafPopup], STEP14) request the same curve with its own cap
/// proportions instead of the marker's default [LeafCapFractions].
class LeafClipper extends CustomClipper<Path> {
  const LeafClipper({
    this.capTopFraction = LeafCapFractions.top,
    this.capBottomFraction = LeafCapFractions.bottom,
  });

  final double capTopFraction;
  final double capBottomFraction;

  @override
  Path getClip(Size size) => buildLeafPath(
        size,
        capTopFraction: capTopFraction,
        capBottomFraction: capBottomFraction,
      );

  @override
  bool shouldReclip(covariant LeafClipper oldClipper) =>
      oldClipper.capTopFraction != capTopFraction ||
      oldClipper.capBottomFraction != capBottomFraction;
}
