import 'package:flutter/material.dart';

import '../services/installation_id_service.dart';
import '../services/kotonoha_api_service.dart';
import '../services/location_service.dart';

/// Comment entry + post step of "言の葉を繋ぐ" (STEP11) — connects a new,
/// photo-less comment to an existing 言の葉 ([parentId]).
///
/// Modeled closely on CommentInputScreen (STEP7), but deliberately kept as
/// its own screen rather than sharing/complicating that one: a connect
/// post has no camera/photo step, no rate-limit cooldown, and sends
/// `parent_id` instead of an image (docs: Root投稿と接続投稿の違いを明確
/// に維持する).
///
/// Re-fetches the current location right here, immediately before posting
/// — never reuses whatever KotonohaDetailScreen measured when it opened,
/// since the user may have moved since then.
class ConnectCommentInputScreen extends StatefulWidget {
  const ConnectCommentInputScreen({
    super.key,
    required this.parentId,
    this.locationService,
    this.installationIdService,
    this.apiService,
  });

  final int parentId;

  // Injectable so widget tests can supply fakes instead of hitting real
  // platform plugins/network; defaults to the real services otherwise.
  final LocationService? locationService;
  final InstallationIdService? installationIdService;
  final KotonohaApiService? apiService;

  static const maxCommentLength = 50;

  @override
  State<ConnectCommentInputScreen> createState() =>
      _ConnectCommentInputScreenState();
}

class _ConnectCommentInputScreenState
    extends State<ConnectCommentInputScreen> {
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

  bool get _canProceed => !_isPosting && _controller.text.trim().isNotEmpty;

  Future<void> _connect() async {
    final comment = _controller.text.trim();
    if (comment.isEmpty) return;

    setState(() {
      _isPosting = true;
      _errorMessage = null;
    });

    KotonohaPostResult? result;
    try {
      // Always re-fetch right here, immediately before sending — the user
      // may have moved since KotonohaDetailScreen measured the distance.
      final location = await _locationService.getCurrentLocation();
      final installationId = await _installationIdService.getInstallationId();

      result = await _apiService.postConnectedKotonoha(
        parentId: widget.parentId,
        installationId: installationId,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        comment: comment,
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
        title: const Text('言の葉を繋ぎました'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Only this screen closes here; KotonohaDetailScreen (the caller)
    // decides whether to also close itself, returning to the tile list
    // (STEP11 section 3/22 — not all the way back to the map).
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('言の葉を繋ぐ')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'この場所に、あなたの言葉だけを重ねます。写真は追加されません。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLength: ConnectCommentInputScreen.maxCommentLength,
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
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
              ElevatedButton(
                onPressed: _canProceed ? _connect : null,
                child: _isPosting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('繋ぐ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
