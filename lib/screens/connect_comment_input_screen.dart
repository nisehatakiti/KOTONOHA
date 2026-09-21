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
      // Real-device fix: this screen used to be a plain white form, with
      // nothing tying it back to KOTONOHA's own leaf world — see
      // _LeafDecoratedBackground's own doc comment. Input remains the
      // priority: the leaf accent stays low-opacity and off in a corner,
      // and the TextField below gets an explicit white fill (see its
      // decoration) so it never loses contrast against the wash.
      body: _LeafDecoratedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'この場所に、あなたの言葉だけを重ねます。',
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
                    // Explicit white fill — the background behind this
                    // screen now carries a faint green wash/leaf accent,
                    // and the input itself must never lose legibility
                    // because of it.
                    filled: true,
                    fillColor: Colors.white,
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
                  // Real-device fix: an explicit natural green instead of
                  // Material 3's default pale tonal surface — see
                  // KotonohaDetailScreen's own 繋ぐ button for the same
                  // change/reasoning. Size/position/tap area and the
                  // _canProceed-gated enable/disable logic, plus
                  // _connect's own save/send behavior, are unchanged.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C7A3D),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF4C7A3D).withValues(alpha: 0.38),
                    disabledForegroundColor: Colors.white70,
                  ),
                  onPressed: _canProceed ? _connect : null,
                  child: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('繋ぐ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet KOTONOHA-leaf-motif background for "言の葉を繋ぐ" (real-device
/// fix: this screen used to be plain white — see its call site). Mirrors
/// [KotonohaDetailScreen]'s own version of this: a pale green wash plus
/// the same generated leaf artwork used elsewhere in the app
/// (assets/design/leaf_marker.png — this screen's own accent, distinct
/// from the detail screen's, so the two don't look identical), shown very
/// faint and tucked into a corner well clear of the input field. No shape
/// is drawn in code — [Opacity] + [Positioned] is the only styling
/// applied to the image itself.
class _LeafDecoratedBackground extends StatelessWidget {
  const _LeafDecoratedBackground({required this.child});

  final Widget child;

  static const _washColor = Color(0xFFF3F9EE);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _washColor,
      child: Stack(
        // Clips the corner-peeking leaf image to the screen's own bounds
        // — a plain rectangular clip on the *container*, not a leaf-
        // shaped clip on the artwork itself.
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            // Real-device fix: sized up a little from the original 200px
            // accent (still low-opacity, still tucked into the corner,
            // still well clear of the input field) — the offset grows by
            // the same proportion so it keeps peeking in by about the
            // same amount rather than intruding further.
            left: -55,
            bottom: -45,
            child: Opacity(
              opacity: 0.09,
              child: Image.asset(
                'assets/design/leaf_marker.png',
                width: 250,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
