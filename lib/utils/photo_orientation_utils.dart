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

/// Like [normalizePhotoOrientation], but bakes [exifOrientation] (a raw
/// Exif Orientation value, 1-8) instead of trusting whatever — possibly
/// missing, possibly stale — Exif Orientation tag [bytes] already
/// carries.
///
/// Real-device fix: on Android, `camera`'s own capture pipeline does not
/// reliably write an Exif Orientation tag that reflects how the phone
/// was actually held at shutter time (confirmed independently of this
/// app's own code, in the `camera` package's own camera_preview.dart —
/// see camera_capture_screen.dart's own doc comment for the full
/// reasoning); trusting that tag was the root cause of landscape shots
/// coming out portrait. [exifOrientation] here is computed by the caller
/// from [CameraController.value.deviceOrientation] instead — a value
/// this app reads directly and knows for certain — and is baked using
/// the *exact same* [img.bakeOrientation] mechanism
/// [normalizePhotoOrientation] uses; this is not a second, duplicate
/// rotation implementation, only a different (trusted) source for which
/// Exif Orientation value gets baked.
///
/// Returns [bytes] unchanged if they can't be decoded as an image.
Uint8List normalizePhotoOrientationWithOverride(Uint8List bytes, int exifOrientation) {
  final decoded = _tryDecode(bytes);
  if (decoded == null) return bytes;

  decoded.exif.imageIfd.orientation = exifOrientation;
  final baked = img.bakeOrientation(decoded);
  return img.encodeJpg(baked, quality: _kReencodeQuality);
}

/// The Exif Orientation value (1/3/6/8) needed to correct Android's
/// fixed-sensor-orientation still-capture buffer for [orientation] — the
/// *exact* mapping the `camera` package's own `CameraPreview` widget
/// uses to rotate the live preview correctly
/// (camera_preview.dart's `_getQuarterTurns`: portraitUp→0 turns,
/// landscapeRight→1 turn (90° CW), portraitDown→2 turns (180°),
/// landscapeLeft→3 turns (270° CW)), re-expressed as the equivalent Exif
/// Orientation constant rather than a widget rotation, since the
/// still-capture buffer and the live preview buffer share the same
/// underlying sensor orientation on that platform. A pure, directly
/// testable function — see camera_capture_screen.dart for where
/// [orientation] itself comes from ([CameraController.value.
/// deviceOrientation], read at shutter time) and why this exists (a
/// real-device fix for landscape shots coming out portrait, traced to
/// the camera plugin's own Exif Orientation tag not reliably reflecting
/// how the phone was actually held).
///
/// Assumes the rear camera — this app's camera screen always opens
/// `availableCameras().first`, the rear camera on every real device it
/// targets — a front camera's mirroring is not accounted for here.
int exifOrientationForDeviceOrientation(DeviceOrientation orientation) {
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      return 1; // Normal — no rotation needed.
    case DeviceOrientation.landscapeRight:
      return 6; // 90° CW needed.
    case DeviceOrientation.portraitDown:
      return 3; // 180° needed.
    case DeviceOrientation.landscapeLeft:
      return 8; // 270° CW (90° CCW) needed.
  }
}

/// [img.decodeImage] returning null already covers "not an image this
/// package recognizes", but some malformed/truncated inputs make one of
/// its format-sniffing decoders throw instead (observed: a too-short
/// buffer during PSD header-sniffing raising a [RangeError]) — caught
/// here so *any* undecodable input reaches [normalizePhotoOrientation]/
/// [normalizePhotoOrientationWithOverride]'s own "return bytes unchanged"
/// fallback, not just the ones that fail cleanly.
img.Image? _tryDecode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}
