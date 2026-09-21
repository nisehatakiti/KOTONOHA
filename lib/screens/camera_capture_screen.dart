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
/// Real-device fix (2nd attempt — see below): no 縦/横 choice, and no
/// manual rotate control, is ever shown to the user. Orientation is
/// corrected automatically and unconditionally at capture time:
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
/// 2. **This screen never reads, trusts, or bakes the resulting file's
///    own Exif Orientation tag at all**, on any platform. The 1st fix
///    attempt still routed through Exif (computing an Exif Orientation
///    value from [DeviceOrientation] and letting `image`'s own
///    `bakeOrientation` interpret it) and was confirmed wrong on real
///    Android hardware — landscape captures still came out portrait. On
///    Android, [_normalizeInPlace] now calls
///    [rotatePhotoForDeviceOrientation] instead, which rotates the pixel
///    data directly using [rotationDegreesForDeviceOrientation]'s answer
///    for the very same [DeviceOrientation] this method just read — see
///    that function's own doc comment for exactly where its rotation
///    mapping comes from (read directly out of
///    `camera_android_camerax`'s own source, not guessed) and why it
///    differs from the 1st attempt's, *and* for why it must strip any
///    Exif Orientation tag from the file **before** decoding it (`image`'s
///    own JPEG decoder auto-applies that tag unconditionally on decode —
///    discovered while building this 2nd fix — so skipping that step
///    would silently double-rotate every capture that arrives with a
///    non-trivial Exif tag already set). Other platforms keep using the
///    original Exif-trusting [normalizePhotoOrientation], since only
///    Android's capture pipeline was confirmed to need this fix.
/// 3. Either way, the resulting file has both correct pixels *and* its
///    Exif Orientation tag reset to Normal — every later reader of this
///    same path (this screen's own preview, CommentInputScreen's
///    preview, the eventual upload) sees a single already-upright image
///    that needs no Exif interpretation at all, ever.
///
/// Real-device fix (full-screen layout pass): this is a *layout-only*
/// change — nothing above (deviceOrientation / lockCaptureOrientation /
/// unlockCaptureOrientation / the Exif-neutralizing decode / the actual
/// pixel rotation in photo_orientation_utils.dart) was touched. Only how
/// the live camera feed is *arranged on screen* changed:
///
/// - The live-camera mode no longer sits inside a `Column` with the
///   shutter button as a sibling `Padding` row below `Expanded(
///   CameraPreview(...))`. That gave [CameraPreview] a box whose *width*
///   was loose but whose *height* was tight (whatever the `Column` had
///   left over after the button row) — in landscape specifically, that
///   left-over height is small relative to the width, so
///   [CameraPreview]'s own internal `AspectRatio` (untouched — see
///   camera_preview.dart) shrank the preview's *width* down to keep the
///   aspect ratio correct within that short box, leaving big empty
///   margins on both sides (「横向きにするとカメラプレビューが小さくな
///   る」). [_FillScreenCameraPreview] fixes this the same way production
///   full-screen-camera apps generally do: give [CameraPreview] a large,
///   *loose* sizing sandbox (so its own `AspectRatio` can compute its
///   true, undistorted natural size, whichever orientation it currently
///   wants) and then apply one single uniform `BoxFit.cover` scale
///   (`FittedBox`) up to fill whatever real space this widget is given —
///   cropping evenly at the edges when the camera's own aspect ratio
///   doesn't match the screen's, never stretching, and never leaving
///   margins.
/// - The shared `Scaffold(appBar: AppBar(title: Text('言の葉を置く')))`
///   that used to wrap *both* the live camera and the post-capture review
///   is now conditional: the review screen (unchanged) still gets that
///   `AppBar`, but live-camera mode gets no `AppBar` at all (its own fixed
///   height was exactly what left the "上下に余白ができる" gap) and never
///   shows "言の葉を置く" anywhere. A back action is still available in
///   camera mode — [_CameraBackButton], overlaid on the video itself
///   inside a `SafeArea` so it clears the status bar/notch without ever
///   shrinking the camera feed, which is *not* wrapped in `SafeArea`.
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
  /// On Android, [capturedOrientation] alone (never the file's own Exif
  /// tag) decides the rotation — see [rotatePhotoForDeviceOrientation].
  /// Other platforms keep using the original Exif-trusting
  /// [normalizePhotoOrientation], since only Android's capture pipeline
  /// was confirmed to need this fix.
  ///
  /// A failure here (corrupt/unreadable bytes) just leaves the file
  /// exactly as the camera produced it rather than blocking the capture
  /// over it.
  Future<void> _normalizeInPlace(File file, DeviceOrientation capturedOrientation) async {
    try {
      final original = await file.readAsBytes();
      final normalized = defaultTargetPlatform == TargetPlatform.android
          ? rotatePhotoForDeviceOrientation(original, capturedOrientation)
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
    if (capturedPhoto != null) {
      // Review mode (post-shutter, before proceeding to the comment
      // screen) is unchanged — its own existing AppBar/SafeArea/layout,
      // untouched by this full-screen-camera pass.
      return Scaffold(
        appBar: AppBar(title: const Text('言の葉を置く')),
        body: SafeArea(child: _buildReview(capturedPhoto)),
      );
    }

    // Live-camera mode: no AppBar (see class doc comment above for why),
    // black background so any letterbox-free edge that briefly shows
    // before the first frame reads as "camera", not as a layout gap.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(),
          // Overlaid on top of the video itself, inside its own SafeArea
          // — clears the status bar/notch without the camera feed behind
          // it (deliberately outside any SafeArea) ever shrinking for it.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.topLeft,
                child: _CameraBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The live-camera mode's entire content below the back-button overlay:
  /// the error message, the loading spinner, or (once ready) the actual
  /// full-screen preview plus the shutter button — every one of these
  /// fills the whole [Stack] it's placed in (`StackFit.expand` in [build]
  /// makes a non-[Positioned] child like this one fill its parent).
  Widget _buildCameraLayer() {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
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
        return Stack(
          fit: StackFit.expand,
          children: [
            _FillScreenCameraPreview(controller: controller),
            // 画面下部中央 — the shutter button floats on top of the
            // video, inside its own SafeArea so it clears the bottom
            // system gesture area without the video behind it shrinking.
            SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FloatingActionButton(
                  onPressed: _takePhoto,
                  child: const Icon(Icons.camera_alt),
                ),
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

/// Scales [controller]'s live preview ([CameraPreview] — a complete,
/// self-contained widget that already picks the correct proportions and
/// rotation for the current device orientation entirely on its own via
/// its own internal `AspectRatio`/`RotatedBox`, both fully untouched here;
/// see camera_preview.dart) up (or down) to cover every pixel of the
/// space this widget is given, cropping evenly at the edges rather than
/// ever leaving margins — docs section 6: 画面いっぱいに表示することを
/// 優先し、必要であればカメラ映像の一部がクロップされることは許容する.
///
/// [_sizingSandbox] exists only because [FittedBox] hands its child fully
/// *unbounded* constraints, and [CameraPreview]'s own internal
/// `AspectRatio` cannot compute anything at all without *some* finite
/// bound to work within. The sandbox's own absolute size is otherwise
/// meaningless: [CameraPreview] always resolves to its own true,
/// undistorted proportions inside it (whichever orientation it currently
/// wants — this widget never inspects or duplicates that decision), and
/// the single uniform `BoxFit.cover` scale that follows is computed
/// against this widget's *real* incoming constraints (the actual on-
/// screen area), not the sandbox — so the sandbox's size never appears in
/// the final rendered result.
class _FillScreenCameraPreview extends StatelessWidget {
  const _FillScreenCameraPreview({required this.controller});

  final CameraController controller;

  static const _sizingSandbox = BoxConstraints(maxWidth: 4096, maxHeight: 4096);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: ConstrainedBox(
          constraints: _sizingSandbox,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// The camera screen's own "戻る" action (docs section 4) — a plain
/// [AppBar] back button isn't available in live-camera mode (there is no
/// AppBar; see the class doc comment above), so this sits directly on top
/// of the video feed instead. A translucent circular backing keeps the
/// white arrow legible over arbitrary video content, whatever's actually
/// in frame.
class _CameraBackButton extends StatelessWidget {
  const _CameraBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: '戻る',
        onPressed: onPressed,
      ),
    );
  }
}
