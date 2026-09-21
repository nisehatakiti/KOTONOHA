import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../services/location_service.dart';
import '../utils/distance_utils.dart';
import '../utils/kotonoha_format.dart';
import '../widgets/leaf_decorated_section.dart';
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
            LeafDecoratedSection(
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
                      // Real-device fix: Material 3's default ElevatedButton
                      // is a pale tonal surface, not a solid color — reading
                      // as another generic form control rather than part of
                      // KOTONOHA's own green identity. Explicit styling
                      // only; size/padding/position/tap area and the
                      // button's onPressed logic (canConnect gating,
                      // _onConnectPressed) are unchanged.
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4C7A3D),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF4C7A3D).withValues(alpha: 0.38),
                        disabledForegroundColor: Colors.white70,
                      ),
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

/// Real-device fix: this used to also show "距離を確認しています…" while
/// [isLoading], and once resolved, the specific distance readout (e.g.
/// 「繋げる距離 あと4m」) — both called out on the latest UI pass as
/// user-facing clutter KOTONOHA doesn't need. [isLoading]/[distanceMeters]/
/// [distanceState] are kept as constructor parameters (unused by [build]
/// now) rather than removed, since the distance computation/gating they
/// come from ([KotonohaDetailScreen._measureDistance],
/// `canConnect`/「繋ぐ」's enabled state) is unchanged — only this
/// widget's own display of them is trimmed. [errorMessage] is kept
/// visible: a genuine location-fetch failure is still worth surfacing to
/// the user, the same reasoning as HomeScreen's own location-failure
/// notice (see _LocationDebugPanel there).
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
    final error = errorMessage;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        error,
        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
      ),
    );
  }
}
