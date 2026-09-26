import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:kotonoha/widgets/leaf_marker_icon.dart';

/// 画像アセット置換 (real-device fix): the map marker artwork changed from
/// a standing leaf to one lying flat with a ground shadow. GoogleMap
/// itself never spins up in `flutter test` (see kotonoha_map_test.dart's
/// own header comment), so the actual on-map [Marker] this asset feeds
/// can't be exercised here — this file instead verifies the asset
/// reference itself: [kLeafAsset] points at a real file, and
/// [kLeafAssetNativeWidth]/[kLeafAssetNativeHeight] match that file's
/// *actual* decoded dimensions, so a future asset regeneration that
/// changes its size can't silently leave these constants stale.
void main() {
  test('kLeafAsset points at a file that actually exists', () {
    expect(File(kLeafAsset).existsSync(), isTrue, reason: kLeafAsset);
  });

  test(
    'kLeafAssetNativeWidth/Height match the real asset\'s decoded pixel '
    'dimensions',
    () {
      final decoded = img.decodeImage(File(kLeafAsset).readAsBytesSync())!;
      expect(decoded.width, kLeafAssetNativeWidth.round());
      expect(decoded.height, kLeafAssetNativeHeight.round());
    },
  );

  test(
    'the asset has real alpha transparency around the leaf (not a flat '
    'white/opaque background) — every corner is fully transparent',
    () {
      final decoded = img.decodeImage(File(kLeafAsset).readAsBytesSync())!;
      for (final (x, y) in [
        (0, 0),
        (decoded.width - 1, 0),
        (0, decoded.height - 1),
        (decoded.width - 1, decoded.height - 1),
      ]) {
        expect(decoded.getPixel(x, y).a, 0, reason: 'corner ($x,$y)');
      }
    },
  );
}
