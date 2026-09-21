import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../utils/photo_orientation_utils.dart';
import 'comment_input_screen.dart';

/// Camera capture step of "言の葉を置く" (docs/ui.md section 3).
///
/// Always uses the in-app camera — gallery/file picking is intentionally
/// not offered (docs/requirements.md section 1: 写真ライブラリから既存写
/// 真を選択できない). Nothing is persisted here: the captured file only
/// lives wherever the camera plugin puts its temporary output, and is
/// passed forward in-memory until a later STEP wires up the actual
/// POST /api/kotonoha upload (docs/api.md section 5).
///
/// Real-device fix: no 縦/横 choice, and no manual rotate control, is ever
/// shown to the user. Orientation is corrected automatically and
/// unconditionally at capture time:
///
/// 1. [_takePhoto] reads the device's own physical orientation at the
///    exact moment of the shutter press ([CameraController.value.
///    deviceOrientation] — tracked continuously by the plugin itself once
///    [CameraController.initialize] has run, via its own device-
///    orientation-sensor listener; nothing extra to wire up here), locks
///    the capture to exactly that orientation
///    ([CameraController.lockCaptureOrientation]) *before* calling
///    [CameraController.takePicture], and releases the lock afterward
///    ([CameraController.unlockCaptureOrientation], in a `finally` block
///    so a subsequent "撮り直す" capture isn't left pinned to a stale
///    reading).
/// 2. **Real-device fix (2)**: the lock above does *not*, by itself,
///    reliably make the resulting file's own Exif Orientation tag
///    correct on Android — confirmed by reading the `camera` package's
///    own source (`camera_preview.dart`): on Android specifically, the
///    plugin's *live preview* is known to come out of the sensor in a
///    fixed, device-orientation-independent buffer orientation, which is
///    why `CameraPreview` itself wraps the preview texture in a
///    `RotatedBox` — using an explicit `deviceOrientation`-keyed
///    quarter-turn table (`portraitUp`→0, `landscapeRight`→1,
///    `portraitDown`→2, `landscapeLeft`→3), not Exif — to correct it.
///    The still-capture pipeline shares that same sensor buffer, so this
///    screen mirrors that *exact, already-proven-correct* table
///    ([_exifOrientationForDeviceOrientation]) to decide the Exif
///    Orientation value to bake on Android, instead of trusting whatever
///    the camera plugin itself wrote. This is what actually fixes
///    "横向きで撮影すると縦向きになる": trusting the file's own
///    (unreliable, on Android) Exif tag was the root cause. iOS's
///    AVFoundation is a different, separately-implemented capture
///    pipeline that does reliably Exif-tag its own output, so this
///    override only applies on Android
///    ([_normalizeInPlace]/[defaultTargetPlatform]) — other platforms
///    still use the original Exif-trusting [normalizePhotoOrientation].
/// 3. Either way, the resulting pixels are baked and the Exif tag itself
///    is reset to Normal via the *same* `image`-package mechanism
///    ([img.bakeOrientation], inside [normalizePhotoOrientation] /
///    [normalizePhotoOrientationWithOverride] — no separate/duplicate
///    rotation implementation exists here). Every later reader of this
///    same file — this screen's own preview, CommentInputScreen's
///    preview, the eventual upload — sees a single already-upright image
///    with no Exif Orientation left to separately interpret.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _errorMessage;
  XFile? _capturedPhoto;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = 'カメラが見つかりませんでした。');
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _messageFor(e));
    }
  }

  String _messageFor(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'カメラの権限が許可されていません。端末の設定でKOTONOHAのカメラ権限を許可してください。';
      default:
        return 'カメラを起動できませんでした。';
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // 撮影時のorientationを確定: read the plugin's own continuously-
    // updated deviceOrientation synchronously, right before locking/
    // capturing — this is the one moment this value is read; it is never
    // re-derived later from the resulting file's own Exif.
    final orientation = controller.value.deviceOrientation;

    try {
      // Pins this one shot's own JPEG-orientation encoding to exactly
      // this reading (see the class doc comment above for why this,
      // rather than a fixed/guessed rotation angle, is what actually
      // fixes inconsistent real-device orientation).
      await controller.lockCaptureOrientation(orientation);
      final photo = await controller.takePicture();
      await _normalizeInPlace(File(photo.path), orientation);
      if (!mounted) return;
      setState(() => _capturedPhoto = photo);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撮影に失敗しました。もう一度お試しください。')),
      );
    } finally {
      // Releases the lock so a subsequent "撮り直す" capture goes back to
      // tracking whatever orientation the phone is held in *then*,
      // rather than staying pinned to this shot's own reading.
      if (mounted) {
        try {
          await controller.unlockCaptureOrientation();
        } catch (_) {
          // Best-effort only — nothing else to do if this fails.
        }
      }
    }
  }

  /// Physically rotates [file]'s pixel data in place and resets its Exif
  /// Orientation tag to Normal — see the class doc comment above — so
  /// every later read of this same path (this screen's own preview
  /// below, CommentInputScreen's preview, the eventual upload) sees a
  /// single already-upright image, with no Exif Orientation left for
  /// anything downstream to separately interpret.
  ///
  /// On Android, [capturedOrientation] (not the file's own Exif tag) is
  /// what actually decides the rotation — see
  /// [_exifOrientationForDeviceOrientation]. Other platforms keep using
  /// the original Exif-trusting [normalizePhotoOrientation], since only
  /// Android's capture pipeline was confirmed to need this override.
  ///
  /// A failure here (corrupt/unreadable bytes) just leaves the file
  /// exactly as the camera produced it rather than blocking the capture
  /// over it.
  Future<void> _normalizeInPlace(File file, DeviceOrientation capturedOrientation) async {
    try {
      final original = await file.readAsBytes();
      final normalized = defaultTargetPlatform == TargetPlatform.android
          ? normalizePhotoOrientationWithOverride(
              original,
              exifOrientationForDeviceOrientation(capturedOrientation),
            )
          : normalizePhotoOrientation(original);
      await file.writeAsBytes(normalized);
    } catch (_) {
      // Leave the file untouched.
    }
  }

  void _retake() {
    setState(() => _capturedPhoto = null);
  }

  void _next() {
    final photo = _capturedPhoto;
    if (photo == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CommentInputScreen(photo: photo)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capturedPhoto = _capturedPhoto;
    return Scaffold(
      appBar: AppBar(title: const Text('言の葉を置く')),
      body: SafeArea(
        child: capturedPhoto != null
            ? _buildReview(capturedPhoto)
            : _buildCameraPreview(),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(errorMessage, textAlign: TextAlign.center),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (snapshot.connectionState != ConnectionState.done ||
            controller == null ||
            !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(child: CameraPreview(controller)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FloatingActionButton(
                onPressed: _takePhoto,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReview(XFile photo) {
    return Column(
      children: [
        Expanded(
          // 縦/横どちらの写真でも常にBoxFit.contain — 元の縦横比を維持し
          // 全体を表示する（トリミングしない）。写真の向き自体は撮影直後
          // に自動で正規化済み（_takePhoto → _normalizeInPlace）なので、
          // ここで縦/横用に別レイアウトへ分岐する必要はなく、ユーザーが
          // 向きを直す操作（回転ボタン等）も一切ない。
          child: Image.file(File(photo.path), fit: BoxFit.contain),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _retake,
                  child: const Text('撮り直す'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _next,
                  child: const Text('次へ'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
