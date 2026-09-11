import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'comment_input_screen.dart';

/// Camera capture step of "言の葉を置く" (docs/ui.md section 3).
///
/// Always uses the in-app camera — gallery/file picking is intentionally
/// not offered (docs/requirements.md section 1: 写真ライブラリから既存写
/// 真を選択できない). Nothing is persisted here: the captured file only
/// lives wherever the camera plugin puts its temporary output, and is
/// passed forward in-memory until a later STEP wires up the actual
/// POST /api/kotonoha upload (docs/api.md section 5).
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
    try {
      final photo = await controller.takePicture();
      if (!mounted) return;
      setState(() => _capturedPhoto = photo);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撮影に失敗しました。もう一度お試しください。')),
      );
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
        Expanded(child: Image.file(File(photo.path), fit: BoxFit.contain)),
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
