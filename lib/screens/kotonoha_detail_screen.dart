import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../services/location_service.dart';
import '../utils/distance_utils.dart';
import '../utils/kotonoha_format.dart';
import 'connect_comment_input_screen.dart';

/// "見える → 触れる" detail view for a single 言の葉 (STEP10-B), opened via
/// the "詳細" button on KotonohaLeafPopup (STEP11-UI), reachable only once
/// the user is within 5m (docs section 8).
///
/// Takes the [item] already fetched via `GET /api/kotonoha/{id}` when the
/// popup loaded — this screen never re-fetches it.
///
/// Reads the current location exactly once (no stream/continuous
/// tracking — see LocationService) to compute the distance to the 言の葉's
/// post location, purely to decide whether "繋ぐ" is enabled here.
class KotonohaDetailScreen extends StatefulWidget {
  const KotonohaDetailScreen({super.key, required this.item, this.locationService});

  final KotonohaItem item;

  // Injectable so widget tests can supply a fake instead of hitting real
  // platform plugins; defaults to the real service otherwise.
  final LocationService? locationService;

  @override
  State<KotonohaDetailScreen> createState() => _KotonohaDetailScreenState();
}

class _KotonohaDetailScreenState extends State<KotonohaDetailScreen> {
  late final _locationService = widget.locationService ?? LocationService();

  bool _isLoadingDistance = true;
  double? _distanceMeters;
  String? _distanceErrorMessage;

  @override
  void initState() {
    super.initState();
    _measureDistance();
  }

  Future<void> _measureDistance() async {
    try {
      final current = await _locationService.getCurrentLocation();
      final meters = calculateDistanceMeters(
        startLatitude: current.latitude,
        startLongitude: current.longitude,
        endLatitude: widget.item.latitude,
        endLongitude: widget.item.longitude,
      );
      if (!mounted) return;
      setState(() {
        _distanceMeters = meters;
        _isLoadingDistance = false;
      });
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _distanceErrorMessage = describeLocationFailure(e.reason);
        _isLoadingDistance = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _distanceErrorMessage = '距離を確認できませんでした。';
        _isLoadingDistance = false;
      });
    }
  }

  Future<void> _onConnectPressed() async {
    final parentId = int.parse(widget.item.id);
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectCommentInputScreen(parentId: parentId),
      ),
    );
    // A successful connect pops this detail screen too, returning to the
    // tile list underneath (STEP11 section 3/22) — never all the way back
    // to the map.
    if (connected == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final distanceMeters = _distanceMeters;
    final distanceState = distanceMeters == null
        ? null
        : classifyDistanceState(distanceMeters);
    final canConnect = distanceState == KotonohaDistanceState.connectable;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Photo(imageUrl: item.imageUrl)),
            _LeafDecoratedInfoSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.comment, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 12),
                  Text(
                    formatKotonohaDateTime(item.createdAt),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  _DistanceStatus(
                    isLoading: _isLoadingDistance,
                    errorMessage: _distanceErrorMessage,
                    distanceMeters: distanceMeters,
                    distanceState: distanceState,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canConnect ? _onConnectPressed : null,
                      child: const Text('繋ぐ'),
                    ),
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

/// Wraps the detail screen's photo-below info column in a quiet KOTONOHA-
/// leaf-motif background (real-device fix: this area used to be plain
/// white, reading as a generic form rather than part of KOTONOHA's own
/// world) — a pale green wash plus the same generated leaf artwork
/// already used elsewhere in the app
/// (assets/design/leaf_popup.png), shown very faint and peeking in from a
/// corner rather than filling the screen, so it never competes with the
/// photo above it (still the screen's one visual focus) or the text on
/// top of it. No shape is drawn in code here — [Opacity] + [Positioned]
/// is the only styling applied to the image itself.
class _LeafDecoratedInfoSection extends StatelessWidget {
  const _LeafDecoratedInfoSection({required this.child});

  final Widget child;

  static const _washColor = Color(0xFFF3F9EE);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _washColor,
      child: Stack(
        // Clips the corner-peeking leaf image to this section's own
        // bounds — a plain rectangular clip on the *container*, not a
        // leaf-shaped clip on the artwork itself.
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -36,
            top: -28,
            child: Opacity(
              opacity: 0.10,
              child: Image.asset(
                'assets/design/leaf_popup.png',
                width: 168,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return Container(color: Colors.grey.shade300);
    }
    return Image.network(
      url,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey.shade300,
        child: Center(
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

class _DistanceStatus extends StatelessWidget {
  const _DistanceStatus({
    required this.isLoading,
    required this.errorMessage,
    required this.distanceMeters,
    required this.distanceState,
  });

  final bool isLoading;
  final String? errorMessage;
  final double? distanceMeters;
  final KotonohaDistanceState? distanceState;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Text('距離を確認しています…', style: TextStyle(fontSize: 12));
    }

    final error = errorMessage;
    if (error != null) {
      return Text(
        error,
        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
      );
    }

    final meters = distanceMeters;
    final state = distanceState;
    if (meters == null || state == null) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          describeDistanceState(state),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Text(formatDistanceMeters(meters), style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
