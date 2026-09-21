import 'dart:typed_data';

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
/// Real-device fix (3rd attempt): used for **every** platform, including
/// Android — see camera_capture_screen.dart's own class doc comment for
/// the full reasoning behind reverting the 2nd attempt's
/// deviceOrientation-only override (`rotatePhotoForDeviceOrientation`,
/// removed) back to trusting the file's own Exif Orientation tag. In
/// short: that 2nd attempt computed its own rotation from
/// [DeviceOrientation] alone, using a fixed table that never read the
/// camera's *own* sensor mounting angle
/// ([CameraDescription.sensorOrientation]) at all — confirmed wrong on
/// real hardware (a landscape capture came out portrait, rotated 90°).
/// [CameraController.lockCaptureOrientation] (still called, unchanged,
/// right before every [CameraController.takePicture] — see
/// camera_capture_screen.dart) is CameraX's own documented mechanism for
/// making the Exif Orientation tag it writes correct in the first place,
/// already accounting for that device-specific sensor angle internally —
/// this function just has to bake whatever tag results, exactly as it
/// always did for non-Android platforms.
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

/// [img.decodeImage] returning null already covers "not an image this
/// package recognizes", but some malformed/truncated inputs make one of
/// its format-sniffing decoders throw instead (observed: a too-short
/// buffer during PSD header-sniffing raising a [RangeError]) — caught
/// here so *any* undecodable input reaches [normalizePhotoOrientation]'s
/// own "return bytes unchanged" fallback, not just the ones that fail
/// cleanly.
img.Image? _tryDecode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

/// A one-line diagnostic summary of [bytes] as a JPEG, for the debug
/// logging camera_capture_screen.dart adds around every capture
/// (real-device fix, 3rd attempt — instructions item 3 asks for exactly
/// this: deviceOrientation, sensor orientation, JPEG width/height, Exif
/// Orientation, logged from the raw capture *before* this module's own
/// [normalizePhotoOrientation] ever touches it, so the true camera output
/// — not this app's own interpretation of it — is what gets compared
/// across portrait/landscapeRight/landscapeLeft/180° on a real device).
///
/// "rawWidth"/"rawHeight" are the JPEG's own raw SOF-marker pixel
/// dimensions — *not* run through [img.decodeImage]'s own mandatory auto-
/// bake (see [normalizePhotoOrientation]'s doc comment: that bake, and
/// the tag-clearing that comes with it, can't be opted out of via the
/// public decode API) — obtained by stripping the Orientation tag first
/// (via the same public [img.decodeJpgExif]/[img.injectJpgExif] API the
/// now-removed 2nd attempt used) so decoding can't apply it, then
/// decoding. "exifOrientation" is read straight from the *original*,
/// un-stripped bytes — the literal tag value the camera actually wrote
/// (or `none` if absent).
///
/// Never throws; returns a fixed "undecodable" string instead on failure
/// — a logging helper must never be able to crash the capture flow it's
/// only observing.
String describeJpegForDebugLog(Uint8List bytes) {
  try {
    final rawExif = img.decodeJpgExif(bytes);
    final exifOrientation = (rawExif != null && rawExif.imageIfd.hasOrientation)
        ? rawExif.imageIfd.orientation.toString()
        : 'none';

    final decoded = _tryDecode(_withExifOrientationStripped(bytes));
    if (decoded == null) {
      return 'undecodable (${bytes.length} bytes) exifOrientation=$exifOrientation';
    }
    return 'rawWidth=${decoded.width} rawHeight=${decoded.height} '
        'exifOrientation=$exifOrientation';
  } catch (_) {
    return 'undecodable (${bytes.length} bytes)';
  }
}

/// Strips any Exif Orientation tag from [bytes] so a later
/// [img.decodeImage] can't auto-bake it — used only by
/// [describeJpegForDebugLog], purely to read a JPEG's true raw SOF pixel
/// dimensions for the debug log. Returns [bytes] unchanged if there's no
/// tag to strip, or the Exif/JPEG structure can't be parsed.
Uint8List _withExifOrientationStripped(Uint8List bytes) {
  final exif = img.decodeJpgExif(bytes);
  if (exif == null || !exif.imageIfd.hasOrientation) return bytes;
  exif.imageIfd.orientation = null;
  return img.injectJpgExif(bytes, exif) ?? bytes;
}
