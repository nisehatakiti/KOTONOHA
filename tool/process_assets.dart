// One-off asset-processing script for the 画像アセット置換 pass — not part
// of the app itself, run manually via `dart run tool/process_assets.dart`.
// Turns the two raw generated illustrations under assets/design/ into the
// actual files the app/Android build references. Kept in the repo (rather
// than deleted after running) so the exact same transform can be re-run if
// either source image is regenerated later.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  _processLeafMarker();
  print('---');
  _processAppIcon();
}

/// Trims a_clean_minimal_studio_style_illustration_on_a_wh.png (already
/// transparent outside the leaf+shadow) to its content bounding box and
/// downsizes it to a small map-marker-appropriate resolution, saved over
/// assets/design/leaf_marker.png (same path every existing reference —
/// leaf_marker_icon.dart, connect_comment_input_screen.dart — already
/// uses).
void _processLeafMarker() {
  final srcPath =
      'assets/design/a_clean_minimal_studio_style_illustration_on_a_wh.png';
  final src = img.decodeImage(File(srcPath).readAsBytesSync())!;
  print('leaf marker source: ${src.width}x${src.height}, '
      'numChannels=${src.numChannels}');

  final trimmed = img.trim(src, mode: img.TrimMode.transparent, padding: 4);
  print('trimmed: ${trimmed.width}x${trimmed.height}');

  // Old leaf_marker.png (the standing leaf it replaces) was 154x311 —
  // small on purpose, since Marker bitmaps are only ever displayed at a
  // logical height around 70-90px (see leaf_marker_icon.dart/kotonoha_map.dart).
  // This new artwork is landscape (lying flat) rather than portrait, so
  // sizing off its long edge (whichever axis that is) keeps it similarly
  // crisp without carrying a needlessly large PNG into the app bundle.
  const targetLongEdge = 360;
  final longEdge = trimmed.width > trimmed.height ? trimmed.width : trimmed.height;
  final scale = targetLongEdge / longEdge;
  final resized = img.copyResize(
    trimmed,
    width: (trimmed.width * scale).round(),
    height: (trimmed.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  print('resized: ${resized.width}x${resized.height}');

  final outPath = 'assets/design/leaf_marker.png';
  File(outPath).writeAsBytesSync(img.encodePng(resized));
  print('wrote $outPath (${File(outPath).lengthSync()} bytes)');
}

/// Removes a_high_quality_app_icon_style_illustration_on_a_tr.png's white
/// studio background via a 4-connected flood fill seeded from every
/// corner (LAB color-distance threshold, not a blanket "all white pixels"
/// pass — this only clears the background region actually *connected* to
/// a corner, so isolated bright highlights/glow inside the artwork itself
/// are left alone), then produces the two composites
/// flutter_launcher_icons needs:
///   - assets/icons/app_icon_foreground.png — the trimmed, transparent
///     artwork alone, padded so its content sits inside Android's
///     Adaptive Icon safe zone (the center ~66% of the 108x108dp canvas).
///   - assets/icons/app_icon_legacy.png — the same artwork centered over
///     a flattened white square, for pre-Android-8 launchers that don't
///     understand adaptive icons at all.
void _processAppIcon() {
  final srcPath =
      'assets/design/a_high_quality_app_icon_style_illustration_on_a_tr.png';
  var src = img.decodeImage(File(srcPath).readAsBytesSync())!;
  print('app icon source: ${src.width}x${src.height}, '
      'numChannels=${src.numChannels}');

  // Flood fill needs an alpha channel to actually make anything
  // transparent — the source is a flat white-background PNG (likely RGB,
  // no alpha), so convert first.
  if (!src.hasAlpha) {
    src = src.convert(numChannels: 4);
  }

  const threshold = 18.0; // LAB distance — generous enough for anti-
  // aliased near-white edge pixels, tight enough not to eat the leaf's
  // own pale-green highlights.
  final corners = [
    (0, 0),
    (src.width - 1, 0),
    (0, src.height - 1),
    (src.width - 1, src.height - 1),
  ];
  for (final (x, y) in corners) {
    if (src.getPixel(x, y).a == 0) continue; // already cleared by an earlier corner
    src = img.fillFlood(
      src,
      x: x,
      y: y,
      color: img.ColorRgba8(255, 255, 255, 0),
      threshold: threshold,
    );
  }

  final transparentPath = 'assets/design/app_icon_transparent.png';
  File(transparentPath).writeAsBytesSync(img.encodePng(src));
  print('wrote $transparentPath (background removed, for visual review)');

  final trimmed = img.trim(src, mode: img.TrimMode.transparent, padding: 2);
  print('trimmed artwork: ${trimmed.width}x${trimmed.height}');

  Directory('assets/icons').createSync(recursive: true);

  // Foreground: near-full-bleed (flutter_launcher_icons' own generated
  // mipmap-anydpi-v26/ic_launcher.xml applies its own 16% inset on top of
  // this image — see that XML's <inset android:inset="16%"/> — so this
  // source must NOT pre-shrink the content into the safe zone itself; if
  // it did, the two paddings would stack and the artwork would end up
  // far smaller than intended. 0.94 leaves only a thin edge margin, which
  // combined with the tool's own 16% inset lands the visible artwork at
  // roughly 0.94*(1-0.32) ≈ 64% of the icon — inside Android's ~66% safe
  // zone, matching every mask shape.
  final foreground = _centeredOnCanvas(
    trimmed,
    canvasSize: 1024,
    contentFraction: 0.94,
    background: img.ColorRgba8(0, 0, 0, 0),
  );
  final foregroundPath = 'assets/icons/app_icon_foreground.png';
  File(foregroundPath).writeAsBytesSync(img.encodePng(foreground));
  print('wrote $foregroundPath (${File(foregroundPath).lengthSync()} bytes)');

  // Legacy (pre-adaptive) icon: a bit more fill since there's no OS-level
  // mask cropping it further, on a flattened white square.
  final legacy = _centeredOnCanvas(
    trimmed,
    canvasSize: 1024,
    contentFraction: 0.8,
    background: img.ColorRgba8(255, 255, 255, 255),
  );
  final legacyPath = 'assets/icons/app_icon_legacy.png';
  File(legacyPath).writeAsBytesSync(img.encodePng(legacy));
  print('wrote $legacyPath (${File(legacyPath).lengthSync()} bytes)');
}

/// Scales [content] uniformly so its longest edge is [contentFraction] of
/// [canvasSize], then centers it on a fresh [canvasSize]x[canvasSize]
/// canvas filled with [background].
img.Image _centeredOnCanvas(
  img.Image content, {
  required int canvasSize,
  required double contentFraction,
  required img.Color background,
}) {
  final targetLongEdge = (canvasSize * contentFraction).round();
  final longEdge = content.width > content.height ? content.width : content.height;
  final scale = targetLongEdge / longEdge;
  final resized = img.copyResize(
    content,
    width: (content.width * scale).round(),
    height: (content.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );

  final canvas = img.Image(width: canvasSize, height: canvasSize, numChannels: 4);
  img.fill(canvas, color: background);
  img.compositeImage(
    canvas,
    resized,
    dstX: (canvasSize - resized.width) ~/ 2,
    dstY: (canvasSize - resized.height) ~/ 2,
  );
  return canvas;
}
