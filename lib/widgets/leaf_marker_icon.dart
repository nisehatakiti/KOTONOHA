import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'leaf_shape.dart';

/// Rasterizes a leaf silhouette — pointed tip up, pointed stem-base down —
/// into a [BitmapDescriptor] for the map's Root-post markers (STEP13,
/// docs/map-ui-spec.md section 5): 「誰が見てもできるだけ「葉っぱ」に見え
/// るデザイン」「葉の付け根・茎にあたる部分が地面側の投稿位置を指す」.
///
/// google_maps_flutter markers can't render a Flutter widget directly, so
/// this draws the glyph to an offscreen canvas and encodes it as a PNG.
/// The canvas is deliberately taller than it is wide (a vertical leaf, not
/// a round icon): the leaf body ([buildLeafPath]) fills the top
/// `height - stemLength` pixels, and a short stem is drawn straight down
/// from its tip to the very last pixel row. [Marker] defaults to anchoring
/// at a bitmap's bottom-center, so that stem tip — not the leaf body's
/// visual center — is what actually marks the coordinate.
Future<BitmapDescriptor> createLeafMarkerIcon({
  double width = 56,
  double height = 84,
  double stemLength = 10,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height + stemLength));

  final centerX = width / 2;
  final bodySize = Size(width, height);
  final bodyPath = buildLeafPath(bodySize);

  const fillColor = Color(0xFF4A8A3B);
  const lineColor = Color(0xFF2F5C26);

  final fillPaint = Paint()..color = fillColor;
  final outlinePaint = Paint()
    ..color = lineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final veinPaint = Paint()
    ..color = lineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  final stemPaint = Paint()
    ..color = lineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;

  canvas.drawPath(bodyPath, fillPaint);
  canvas.drawPath(bodyPath, outlinePaint);

  // Center vein, tip to base — the simplest possible cue that this is a
  // leaf and not just a generic almond/teardrop, without becoming
  // illustrative (docs section 3: 「過度にイラスト的・装飾的にしない」).
  canvas.drawPath(
    Path()
      ..moveTo(centerX, height * 0.1)
      ..quadraticBezierTo(centerX, height * 0.4, centerX, height),
    veinPaint,
  );
  // One pair of short side veins for texture, kept minimal.
  canvas.drawLine(
    Offset(centerX, height * 0.34),
    Offset(width * 0.30, height * 0.22),
    veinPaint,
  );
  canvas.drawLine(
    Offset(centerX, height * 0.34),
    Offset(width * 0.70, height * 0.22),
    veinPaint,
  );

  // The stem: the base/"硬い部分" pointing straight down at the marker's
  // actual coordinate.
  canvas.drawLine(Offset(centerX, height), Offset(centerX, height + stemLength), stemPaint);

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.round(), (height + stemLength).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}
