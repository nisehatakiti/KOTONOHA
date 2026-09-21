import 'dart:typed_data';

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:image/image.dart' as img;

/// JPEG re-encode quality for [normalizePhotoOrientation] — high enough
/// to stay visually lossless for a single pass, without ballooning the
/// file size back toward the camera's own uncompressed output.
const int _kReencodeQuality = 92;

/// Bakes whatever rotation/flip [bytes]' own Exif Orientation tag
/// describes directly into its pixel data (and resets that tag to
/// "normal"), so every later reader — this app's own preview screens, the
/// uploaded file, and any other client that later displays it — sees a
/// single already-upright image with no Exif Orientation left to
/// separately interpret.
///
/// Deliberately does not infer orientation from raw width/height: a photo
/// held upright by the user can still be stored with landscape pixel
/// dimensions (and vice versa) whenever the sensor was physically rotated
/// relative to how the phone was held — that's exactly what Exif
/// Orientation records, and [img.bakeOrientation] reads that tag, not the
/// dimensions, to decide the correction.
///
/// Returns [bytes] unchanged if they can't be decoded as an image at all
/// — this must never throw and block the capture flow over a single bad
/// frame.
Uint8List normalizePhotoOrientation(Uint8List bytes) {
  final decoded = _tryDecode(bytes);
  if (decoded == null) return bytes;

  final baked = img.bakeOrientation(decoded);
  return img.encodeJpg(baked, quality: _kReencodeQuality);
}

/// Real-device fix (2nd attempt): rotates [bytes]' actual pixel data by
/// [rotationDegreesForDeviceOrientation]'s answer for [orientation] —
/// **never reading, trusting, or baking the file's own Exif Orientation
/// tag at all**. The 1st attempt ([normalizePhotoOrientationWithOverride],
/// removed) still routed through Exif — writing a computed Exif
/// Orientation value onto the decoded image and letting
/// [img.bakeOrientation] interpret *that* — which turned out to still be
/// wrong on real Android hardware for landscape captures. This function
/// has no such indirection: [img.copyRotate] is applied directly, and any
/// Exif Orientation tag the source bytes happen to carry (correct, stale,
/// or absent) is explicitly cleared on the output — it is never consulted
/// to decide the rotation, and it can never come back to double-rotate an
/// already-correct image on a later read.
///
/// **Critical detail this fix depends on**: `package:image`'s own JPEG
/// decoder (the one [img.decodeImage]/[img.decodeJpg] both use —
/// `getImageFromJpeg` in image's own
/// `src/formats/jpeg/_jpeg_quantize_io.dart`) *always* auto-applies
/// whatever Exif Orientation tag a source file happens to carry, baking it
/// into the decoded pixel buffer and clearing the tag, with **no way to
/// opt out via the package's public decode API**. Left alone, that means
/// even this function's own decode step would silently pre-rotate the
/// image first (by whatever the file's *own* Exif tag says — exactly the
/// value this fix must never trust), and then applying
/// [rotationDegreesForDeviceOrientation]'s rotation on top of that would
/// double-rotate it. [_withExifOrientationNeutralized] exists solely to
/// prevent that: it strips any Exif Orientation tag from [bytes] *before*
/// decoding (via the package's own public [img.decodeJpgExif] /
/// [img.injectJpgExif] — no private API, no manual byte-level JPEG
/// parsing), so the decode below is guaranteed to yield the literal,
/// un-reoriented pixel buffer in the camera sensor's own raster order,
/// whatever that source tag said.
///
/// [orientation] must be [CameraController.value.deviceOrientation] read
/// at shutter time — see camera_capture_screen.dart for the full call
/// site and reasoning.
///
/// Returns [bytes] unchanged if they can't be decoded as an image.
Uint8List rotatePhotoForDeviceOrientation(Uint8List bytes, DeviceOrientation orientation) {
  final decoded = _tryDecode(_withExifOrientationNeutralized(bytes));
  if (decoded == null) return bytes;

  final degrees = rotationDegreesForDeviceOrientation(orientation);
  final rotated = degrees == 0 ? img.Image.from(decoded) : img.copyRotate(decoded, angle: degrees);

  // Explicitly clear whatever Exif Orientation tag survived the copy —
  // never bake it, never leave it for a later reader to (mis)interpret.
  // The pixels above are already correct on their own; the tag must
  // agree ("Normal"), not merely go unused.
  rotated.exif.imageIfd.orientation = null;

  return img.encodeJpg(rotated, quality: _kReencodeQuality);
}

/// Returns [bytes] with any Exif Orientation tag (0x0112) removed from its
/// APP1/Exif segment, leaving every other byte — pixel data, all other
/// metadata — untouched. See [rotatePhotoForDeviceOrientation]'s doc
/// comment for exactly why this must run before decoding: it is what
/// keeps [img.decodeImage]'s own mandatory Exif-orientation auto-bake from
/// ever running, not something that itself performs any rotation.
///
/// Built entirely on `package:image`'s public, stable
/// [img.decodeJpgExif]/[img.injectJpgExif] API (no private classes, no
/// hand-rolled JPEG/TIFF byte parsing).
///
/// Returns [bytes] unchanged if it has no Exif data, no Orientation tag,
/// or isn't parseable as JPEG/Exif at all — this must never throw.
Uint8List _withExifOrientationNeutralized(Uint8List bytes) {
  try {
    final exif = img.decodeJpgExif(bytes);
    if (exif == null || !exif.imageIfd.hasOrientation) return bytes;
    exif.imageIfd.orientation = null;
    return img.injectJpgExif(bytes, exif) ?? bytes;
  } catch (_) {
    return bytes;
  }
}

/// The clockwise rotation, in degrees (0/90/180/270), that
/// [rotatePhotoForDeviceOrientation] applies to a still capture taken
/// while the device's own physical orientation was [orientation].
///
/// A pure, directly testable function. The mapping itself —
/// `portraitUp: 0°, landscapeLeft: 90°, portraitDown: 180°,
/// landscapeRight: 270°` — comes from reading `camera_android_camerax`'s
/// own source directly (not assumed, not guessed): its
/// `_getRotationConstantFromDeviceOrientation` (lib/src/
/// android_camera_camerax.dart, the function backing
/// [CameraController.lockCaptureOrientation]) maps `portraitUp` →
/// `Surface.ROTATION_0`, `landscapeLeft` → `Surface.ROTATION_90`,
/// `portraitDown` → `Surface.ROTATION_180`, `landscapeRight` →
/// `Surface.ROTATION_270` — i.e. **`landscapeLeft` and `landscapeRight`
/// are the opposite pairing from the 1st attempt's mapping**, which had
/// borrowed `camera_preview.dart`'s own *live-preview* quarter-turn table
/// instead (a different, unrelated rotation the plugin performs only for
/// on-screen preview display) and was confirmed wrong on real hardware
/// for exactly the landscape cases. `portraitUp` → 0° matches every
/// real-device report so far — portrait capture has never been reported
/// broken, only landscape — so it is kept as the one anchor point this
/// mapping is built around.
///
/// **This mapping is this fix's own best-evidence estimate, not something
/// verified against real hardware from this environment (no device is
/// available here) — real-device confirmation for all 4 orientations is
/// required (see camera_capture_screen.dart / the accompanying report)
/// before trusting it further.** If a specific case still comes out wrong
/// on-device, correcting *this one function* (a single switch statement)
/// is the only code change needed — nothing else in the rotation pipeline
/// depends on which way the mapping actually points.
///
/// Assumes the rear camera — this app's camera screen always opens
/// `availableCameras().first`, the rear camera on every real device it
/// targets — a front camera's mirroring is not accounted for here.
int rotationDegreesForDeviceOrientation(DeviceOrientation orientation) {
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      return 0;
    case DeviceOrientation.landscapeLeft:
      return 90;
    case DeviceOrientation.portraitDown:
      return 180;
    case DeviceOrientation.landscapeRight:
      return 270;
  }
}

/// [img.decodeImage] returning null already covers "not an image this
/// package recognizes", but some malformed/truncated inputs make one of
/// its format-sniffing decoders throw instead (observed: a too-short
/// buffer during PSD header-sniffing raising a [RangeError]) — caught
/// here so *any* undecodable input reaches [normalizePhotoOrientation]/
/// [rotatePhotoForDeviceOrientation]'s own "return bytes unchanged"
/// fallback, not just the ones that fail cleanly.
img.Image? _tryDecode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}
