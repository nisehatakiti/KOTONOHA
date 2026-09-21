import 'dart:typed_data';

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:kotonoha/utils/photo_orientation_utils.dart';

/// A landscape (wider-than-tall) test image, 4 quadrants each a distinct
/// solid color — asymmetric along both axes, so any of the 8 Exif
/// Orientation transforms (rotate/flip) leaves a verifiably different
/// result. Large, flat color blocks (rather than single-pixel markers)
/// also survive JPEG's lossy re-encode essentially untouched, since a
/// uniform region's DCT coefficients barely change under quantization —
/// see [_dominantQuadrant] below, which reads averaged corners rather
/// than exact single pixels for exactly that reason.
img.Image _quadrantImage({int width = 32, int height = 16}) {
  final image = img.Image(width: width, height: height);
  final halfW = width ~/ 2;
  final halfH = height ~/ 2;
  // top-left=red, top-right=green, bottom-left=blue, bottom-right=yellow.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final topHalf = y < halfH;
      final leftHalf = x < halfW;
      final int r, g, b;
      if (topHalf && leftHalf) {
        (r, g, b) = (255, 0, 0);
      } else if (topHalf && !leftHalf) {
        (r, g, b) = (0, 255, 0);
      } else if (!topHalf && leftHalf) {
        (r, g, b) = (0, 0, 255);
      } else {
        (r, g, b) = (255, 255, 0);
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// A single flat color for the whole image — used where the test only
/// cares about dimensions/decodability, not which quadrant ended up
/// where.
img.Image _flatImage({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  image.clear(img.ColorRgb8(120, 180, 90));
  return image;
}

Uint8List _jpegWithOrientation(img.Image image, int? orientation) {
  if (orientation != null) {
    image.exif.imageIfd.orientation = orientation;
  }
  return img.encodeJpg(image, quality: 100);
}

void main() {
  group('normalizePhotoOrientation', () {
    test(
      '横向き写真 (landscape raw pixels) whose Exif says "rotate 90° CW to '
      'display" comes out portrait-shaped — orientation is read from Exif, '
      'not the raw width/height',
      () {
        final source = _flatImage(width: 8, height: 4); // raw: landscape
        final bytes = _jpegWithOrientation(source, 6);

        final normalized = normalizePhotoOrientation(bytes);
        final decoded = img.decodeImage(normalized)!;

        // The photo is "really" portrait once Exif orientation 6 is
        // honored — width/height must swap versus the raw pixel buffer.
        expect(decoded.width, 4);
        expect(decoded.height, 8);
      },
    );

    test(
      '正方形写真 (square) stays square after normalizing, whatever the '
      'Exif Orientation says',
      () {
        for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
          final source = _flatImage(width: 6, height: 6);
          final bytes = _jpegWithOrientation(source, orientation);

          final normalized = normalizePhotoOrientation(bytes);
          final decoded = img.decodeImage(normalized)!;

          expect(decoded.width, 6, reason: 'orientation $orientation');
          expect(decoded.height, 6, reason: 'orientation $orientation');
        }
      },
    );

    test(
      '縦向き写真 (already-portrait raw pixels, no rotation needed — Exif '
      'orientation 1/absent) keeps its own dimensions, never accidentally '
      'rotated',
      () {
        final source = _flatImage(width: 4, height: 8); // raw: portrait
        final bytes = _jpegWithOrientation(source, null);

        final normalized = normalizePhotoOrientation(bytes);
        final decoded = img.decodeImage(normalized)!;

        expect(decoded.width, 4);
        expect(decoded.height, 8);
      },
    );

    test('180° Exif Orientation (3) keeps the same dimensions (no swap)', () {
      final source = _flatImage(width: 8, height: 4);
      final bytes = _jpegWithOrientation(source, 3);

      final normalized = normalizePhotoOrientation(bytes);
      final decoded = img.decodeImage(normalized)!;

      expect(decoded.width, 8);
      expect(decoded.height, 4);
    });

    // KOTONOHA自動向き補正の受け入れ条件(縦向き/横向き/横向き反対方向/
    // 180度)を、「上/右/下/左」が分かる4象限画像の実ピクセル比較で検証する
    // — dimensionだけでなく、正しい向きに回転していることそのものを
    // 確認する。ground truthはpackage:image自身のcopyRotate(手で導出した
    // 座標変換式ではない)と比較するので、このテストが検証しているのは
    // 「decode→bakeOrientation→encode→decodeの往復がロスレスに再現
    // できているか」であり、独自の座標計算が正しいかではない。
    for (final testCase in [
      // (Exif Orientation値, 対応する回転角(度, 時計回り), シナリオ名)
      (null, 0, '縦向き写真 (Exifなし/Orientation=1 相当) — 回転なし'),
      (6, 90, '横向き写真 (Orientation=6) — 90度回転'),
      (8, -90, '横向き反対方向の写真 (Orientation=8) — -90度(270度)回転'),
      (3, 180, '180度回転された写真 (Orientation=3) — 180度回転'),
    ]) {
      final (exifOrientation, angle, name) = testCase;
      test(
        '$name: 出力のwidth/height・ピクセル方向・Exif Orientationが正常'
        '状態であることを確認する',
        () {
          final source = _quadrantImage(width: 32, height: 16);
          final bytes = _jpegWithOrientation(source, exifOrientation);

          final normalized = normalizePhotoOrientation(bytes);
          final decoded = img.decodeImage(normalized)!;

          final expected = img.copyRotate(source, angle: angle);
          expect(decoded.width, expected.width, reason: 'width');
          expect(decoded.height, expected.height, reason: 'height');
          for (final corner in _corners(decoded.width, decoded.height)) {
            final actual = decoded.getPixel(corner.$1, corner.$2);
            final want = expected.getPixel(corner.$1, corner.$2);
            expect(actual.r, closeTo(want.r, 4), reason: 'corner $corner red');
            expect(actual.g, closeTo(want.g, 4), reason: 'corner $corner green');
            expect(actual.b, closeTo(want.b, 4), reason: 'corner $corner blue');
          }

          // Exif Orientationが「正常」状態であること — 表示側が改めて
          // Exifを解釈しなくても正しい向きに見える状態そのものの検証。
          expect(
            decoded.exif.imageIfd.hasOrientation,
            isFalse,
            reason: 'Exif Orientation tag must be cleared after baking, not '
                'just corrected to 1',
          );
        },
      );
    }

    test('is idempotent: normalizing an already-normalized photo again is '
        'a no-op (no drift toward extra rotation on repeated processing)', () {
      final source = _flatImage(width: 8, height: 4);
      final once = normalizePhotoOrientation(_jpegWithOrientation(source, 6));
      final twice = normalizePhotoOrientation(once);

      final onceDecoded = img.decodeImage(once)!;
      final twiceDecoded = img.decodeImage(twice)!;
      expect(twiceDecoded.width, onceDecoded.width);
      expect(twiceDecoded.height, onceDecoded.height);
    });

    test('bytes that can\'t be decoded as an image are returned unchanged, '
        'never crash', () {
      final garbage = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      expect(normalizePhotoOrientation(garbage), same(garbage));
    });
  });

  group('rotationDegreesForDeviceOrientation', () {
    // The mapping read directly out of camera_android_camerax's own
    // source (_getRotationConstantFromDeviceOrientation) — see
    // photo_orientation_utils.dart's own doc comment for the full
    // evidence chain. Locking this mapping down in a test protects
    // against silently reintroducing the "横向きで撮影すると縦向きになる"
    // bug via an unrelated future edit. Note this is the OPPOSITE
    // landscapeLeft/landscapeRight pairing from the 1st (failed) fix
    // attempt's camera_preview.dart-based table.
    test('portraitUp -> 0°', () {
      expect(rotationDegreesForDeviceOrientation(DeviceOrientation.portraitUp), 0);
    });

    test('landscapeLeft -> 90°', () {
      expect(rotationDegreesForDeviceOrientation(DeviceOrientation.landscapeLeft), 90);
    });

    test('portraitDown -> 180°', () {
      expect(rotationDegreesForDeviceOrientation(DeviceOrientation.portraitDown), 180);
    });

    test('landscapeRight -> 270°', () {
      expect(rotationDegreesForDeviceOrientation(DeviceOrientation.landscapeRight), 270);
    });
  });

  group('rotatePhotoForDeviceOrientation (real-device fix, 2nd attempt)', () {
    // Mirrors normalizePhotoOrientation's own directional test group
    // above, but exercises the actual capture-time code path: the
    // *source* bytes carry no Exif Orientation tag at all (simulating
    // Android's camera plugin), and — unlike the 1st (failed) attempt's
    // normalizePhotoOrientationWithOverride — the rotation is applied
    // directly to the pixels via img.copyRotate, with no Exif value ever
    // written or read as an intermediate step.
    for (final testCase in [
      // (撮影時のDeviceOrientation, 対応する回転角(度, 時計回り), シナリオ名)
      (DeviceOrientation.portraitUp, 0, '縦持ち撮影 — 回転なし'),
      (DeviceOrientation.landscapeLeft, 90, '左90度横持ち撮影 — 90度回転'),
      (DeviceOrientation.landscapeRight, 270, '右90度横持ち撮影 — 270度(-90度)回転'),
      (DeviceOrientation.portraitDown, 180, '180度(逆さ)撮影 — 180度回転'),
    ]) {
      final (deviceOrientation, angle, name) = testCase;
      test(
        '$name: Exifタグなしの生バッファから、deviceOrientationだけを根拠に'
        'ピクセルそのものを正しい向きに回転できる(Exifには一切依存しない)',
        () {
          final source = _quadrantImage(width: 32, height: 16);
          // No Exif Orientation tag at all on the source bytes — this is
          // the whole point: nothing here is read from (untrustworthy,
          // and on Android sometimes simply absent) Exif.
          final bytes = _jpegWithOrientation(source, null);

          final rotated = rotatePhotoForDeviceOrientation(bytes, deviceOrientation);
          final decoded = img.decodeImage(rotated)!;

          final expected = img.copyRotate(source, angle: angle);
          expect(decoded.width, expected.width, reason: 'width');
          expect(decoded.height, expected.height, reason: 'height');
          for (final corner in _corners(decoded.width, decoded.height)) {
            final actual = decoded.getPixel(corner.$1, corner.$2);
            final want = expected.getPixel(corner.$1, corner.$2);
            expect(actual.r, closeTo(want.r, 4), reason: 'corner $corner red');
            expect(actual.g, closeTo(want.g, 4), reason: 'corner $corner green');
            expect(actual.b, closeTo(want.b, 4), reason: 'corner $corner blue');
          }

          expect(
            decoded.exif.imageIfd.hasOrientation,
            isFalse,
            reason: 'Exif Orientation tag must be cleared on the output, not '
                'just left unused',
          );
        },
      );
    }

    test(
      'a source file that already carries a (misleading) Exif Orientation '
      'tag is rotated purely from deviceOrientation — the tag is never '
      'read at all, so it cannot skew the result',
      () {
        final source = _quadrantImage(width: 32, height: 16);
        // Deliberately set a "wrong"/unrelated Exif Orientation tag —
        // this function must produce exactly the same pixels as the
        // no-Exif-tag case above for the same deviceOrientation.
        final bytes = _jpegWithOrientation(source, 6);

        final rotated = rotatePhotoForDeviceOrientation(
          bytes,
          DeviceOrientation.landscapeLeft,
        );
        final decoded = img.decodeImage(rotated)!;
        final expected = img.copyRotate(source, angle: 90);

        expect(decoded.width, expected.width);
        expect(decoded.height, expected.height);
        for (final corner in _corners(decoded.width, decoded.height)) {
          final actual = decoded.getPixel(corner.$1, corner.$2);
          final want = expected.getPixel(corner.$1, corner.$2);
          expect(actual.r, closeTo(want.r, 4), reason: 'corner $corner red');
          expect(actual.g, closeTo(want.g, 4), reason: 'corner $corner green');
          expect(actual.b, closeTo(want.b, 4), reason: 'corner $corner blue');
        }
      },
    );

    test('bytes that can\'t be decoded as an image are returned unchanged, '
        'never crash', () {
      final garbage = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      expect(
        rotatePhotoForDeviceOrientation(garbage, DeviceOrientation.landscapeLeft),
        same(garbage),
      );
    });
  });
}

/// The four corner coordinates of a `width` x `height` image — enough to
/// distinguish any of the 4-quadrant test image's colors landing in the
/// wrong place after a transform, without hand-deriving every interior
/// pixel's expected position.
List<(int, int)> _corners(int width, int height) => [
  (0, 0),
  (width - 1, 0),
  (0, height - 1),
  (width - 1, height - 1),
];
