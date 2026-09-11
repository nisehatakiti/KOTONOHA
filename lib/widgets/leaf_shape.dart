import 'package:flutter/widgets.dart';

/// The vertical, pointed-top/pointed-base "leaf" silhouette shared by
/// every leaf surface in KOTONOHA (STEP13) — the small map marker
/// ([leaf_marker_icon.dart]) and the expanded leaf popup
/// ([KotonohaLeafPopup]) both draw this same shape, just at different
/// sizes, so a tap reads as "the same leaf getting bigger" rather than a
/// switch to an unrelated shape (docs/map-ui-spec.md section 6.2: 「葉っ
/// ぱのシルエットを維持する」).
///
/// A single vertical almond: pointed at the very top (the leaf's tip) and
/// pointed at the very bottom (its base — the point every caller aligns
/// with the actual location it represents; section 5: 「葉の付け根・茎に
/// あたる部分が地面側の投稿位置を指す」).
Path buildLeafPath(Size size) {
  final width = size.width;
  final height = size.height;
  final centerX = width / 2;

  return Path()
    ..moveTo(centerX, 0)
    ..cubicTo(width * 0.97, height * 0.16, width * 0.86, height * 0.52, centerX, height)
    ..cubicTo(width * 0.14, height * 0.52, width * 0.03, height * 0.16, centerX, 0)
    ..close();
}

/// Clips a widget to [buildLeafPath], sized to whatever the child actually
/// lays out as.
class LeafClipper extends CustomClipper<Path> {
  const LeafClipper();

  @override
  Path getClip(Size size) => buildLeafPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
