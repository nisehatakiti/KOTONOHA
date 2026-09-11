import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/installation_id_service.dart';
import '../services/kotonoha_api_service.dart';
import '../services/location_service.dart';

/// Comment entry + final "置く" step of "言の葉を置く" (docs/ui.md section 3,
/// docs/requirements.md section 1).
///
/// docs/requirements.md section 6 requires re-fetching the current
/// location immediately before posting, never reusing whatever was shown
/// earlier on the map — that re-fetch happens in [_place], right before
/// calling `POST /api/kotonoha` (docs/api.md section 5). Distance/rate
/// -limit checks are never computed here; the server decides those.
class CommentInputScreen extends StatefulWidget {
  const CommentInputScreen({
    super.key,
    required this.photo,
    this.locationService,
    this.installationIdService,
    this.apiService,
  });

  final XFile photo;

  // Injectable so widget tests can supply fakes instead of hitting real
  // platform plugins/network; defaults to the real services otherwise.
  final LocationService? locationService;
  final InstallationIdService? installationIdService;
  final KotonohaApiService? apiService;

  static const maxCommentLength = 50;

  @override
  State<CommentInputScreen> createState() => _CommentInputScreenState();
}

class _CommentInputScreenState extends State<CommentInputScreen> {
  final _controller = TextEditingController();
  late final _locationService = widget.locationService ?? LocationService();
  late final _installationIdService =
      widget.installationIdService ?? InstallationIdService();
  late final _apiService = widget.apiService ?? KotonohaApiService();

  bool _isPosting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canProceed => !_isPosting && _controller.text.isNotEmpty;

  Future<void> _place() async {
    setState(() {
      _isPosting = true;
      _errorMessage = null;
    });

    KotonohaPostResult? result;
    try {
      // Always re-fetch right here, immediately before sending — never
      // reuse the position shown earlier on the map.
      final location = await _locationService.getCurrentLocation();
      final installationId = await _installationIdService.getInstallationId();

      result = await _apiService.postKotonoha(
        installationId: installationId,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        comment: _controller.text,
        image: File(widget.photo.path),
      );
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = describeLocationFailure(e.reason));
    } on KotonohaApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      // Stop showing the busy state before any dialog opens below, so the
      // button's spinner doesn't keep animating underneath it.
      if (mounted) setState(() => _isPosting = false);
    }

    if (result == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('言の葉を置きました'),
        content: Text('id: ${result!.id}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('言葉を入力')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Image.file(File(widget.photo.path), fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    maxLength: CommentInputScreen.maxCommentLength,
                    maxLines: 3,
                    enabled: !_isPosting,
                    decoration: const InputDecoration(
                      hintText: 'ここに言葉を入力',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_errorMessage != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  ElevatedButton(
                    onPressed: _canProceed ? _place : null,
                    child: _isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('置く'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
