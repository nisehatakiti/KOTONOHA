import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../models/kotonoha_root_detail.dart';
import '../services/location_service.dart';
import '../utils/distance_utils.dart';
import '../utils/kotonoha_format.dart';
import '../widgets/ad_banner.dart';
import '../widgets/leaf_decorated_section.dart';
import 'connect_comment_input_screen.dart';
import 'kotonoha_detail_screen.dart';

/// The screen reached via "言の葉をひらく" (real-device UI pass) — a
/// compact "words" view: [item]'s own photo shown small and pinned at the
/// top, with its comment ("最初の言葉") and every one of [connectedItems]
/// listed below it in a scrollable area. Tapping the small photo still
/// leads to the large-photo [KotonohaDetailScreen] (entirely unchanged),
/// but that is no longer the only way to reach "繋ぐ" here — see the
/// real-device fix note below.
///
/// AC-01/02/03: the photo sits in its own fixed-size header — roughly
/// half of the screen's available height (an Expanded flex-1 sibling of
/// the flex-1 scrollable words area below it) — outside the scrollable
/// area; only the words scroll, and the photo never moves with them,
/// tapping it or not.
///
/// Real-device UI pass: this header area now also carries the same ad
/// banner and leaf-motif background ([LeafDecoratedSection]) already used
/// on the large-photo KotonohaDetailScreen — neither existed on this
/// screen before. The small photo itself scales down with `BoxFit.contain`
/// rather than `BoxFit.cover`: cover was cropping photos whose aspect
/// ratio didn't match the header box, which crops/distorts the wrong way
/// for the "元画像の縦横比を維持する" requirement; contain only ever
/// shrinks the whole image uniformly to fit inside that box, letterboxing
/// rather than cropping — the entire photo is always visible.
///
/// Real-device fix: this screen used to have no "繋ぐ" entry point of its
/// own — reaching it required tapping the small photo above (a plain
/// [GestureDetector] with no visual affordance, since the earlier
/// zoom_out_map icon overlay was removed) to open KotonohaDetailScreen,
/// where "繋ぐ" actually lived. On a real device this made "繋ぐ" appear
/// to not exist at all — confirmed by tracing the navigation graph, not
/// guessed. This screen now measures the distance to [item] itself
/// (mirroring KotonohaDetailScreen's own [_measureDistance]/`canConnect`
/// logic exactly, same 5m threshold) and shows its own "繋ぐ" button
/// directly below the words list, so it never depends on the user
/// discovering the photo tap. The photo-tap path to KotonohaDetailScreen
/// is left entirely unchanged.
class KotonohaWordsScreen extends StatefulWidget {
  const KotonohaWordsScreen({
    super.key,
    required this.item,
    this.connectedItems = const [],
    this.locationService,
  });

  final KotonohaItem item;

  /// Every one of [item]'s own connected words, straight from
  /// `GET /api/kotonoha/{id}`'s `connections` (already fetched by
  /// HomeScreen before this screen ever opens — this screen makes no
  /// network calls of its own). Shown in full here — unlike the map
  /// popup's own 3-item preview, this dedicated screen has room for all
  /// of them.
  final List<KotonohaConnection> connectedItems;

  /// Used both for this screen's own distance measurement (real-device
  /// fix) and forwarded to [KotonohaDetailScreen] when the photo is
  /// tapped — injectable so widget tests can supply a fake instead of
  /// hitting real platform plugins; defaults to the real service
  /// otherwise (the same pattern KotonohaDetailScreen itself already
  /// uses).
  final LocationService? locationService;

  @override
  State<KotonohaWordsScreen> createState() => _KotonohaWordsScreenState();
}

class _KotonohaWordsScreenState extends State<KotonohaWordsScreen> {
  late final _locationService = widget.locationService ?? LocationService();

  double? _distanceMeters;
  String? _distanceErrorMessage;

  @override
  void initState() {
    super.initState();
    _measureDistance();
  }

  // Mirrors KotonohaDetailScreen._measureDistance exactly (same service,
  // same calculation, same 5m threshold via classifyDistanceState) — this
  // screen's own "繋ぐ" button needs the identical gating logic, not a
  // relaxed or stricter copy of it.
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
      setState(() => _distanceMeters = meters);
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      setState(() => _distanceErrorMessage = describeLocationFailure(e.reason));
    } catch (_) {
      if (!mounted) return;
      setState(() => _distanceErrorMessage = '距離を確認できませんでした。');
    }
  }

  bool get _canConnect {
    final meters = _distanceMeters;
    return meters != null && classifyDistanceState(meters) == KotonohaDistanceState.connectable;
  }

  Future<void> _onConnectPressed() async {
    final parentId = int.parse(widget.item.id);
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectCommentInputScreen(parentId: parentId),
      ),
    );
    // Mirrors KotonohaDetailScreen._onConnectPressed: a successful connect
    // closes this screen too, returning to the tile list/popup underneath.
    if (connected == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openPhoto(BuildContext context) async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KotonohaDetailScreen(item: widget.item, locationService: widget.locationService),
      ),
    );
    // A successful 繋ぐ, reached several screens further down, already
    // pops KotonohaDetailScreen with `true` — forward that the same extra
    // step back up, exactly mirroring how KotonohaDetailScreen itself
    // already forwards ConnectCommentInputScreen's own result.
    if (connected == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final connectedItems = widget.connectedItems;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          children: [
            const AdBanner(),
            Expanded(
              child: LeafDecoratedSection(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Real-device fix: this used to be a fixed 180px
                    // header — far smaller than the "画面の約半分" the
                    // latest UI pass calls for. Now an Expanded flex-1
                    // sibling of the flex-1 scroll area below, so the
                    // photo area and the words area each get roughly
                    // half of the available height, whatever that
                    // happens to be on a given device — still a Column
                    // sibling of the Expanded scroll area, so it's
                    // outside its scroll-free layout and never moves
                    // with the words (AC-01/AC-04).
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openPhoto(context),
                        child: _SmallPhoto(imageUrl: item.imageUrl),
                      ),
                    ),
                    Expanded(
                      // AC-02/AC-03: only this area scrolls — the photo
                      // above is a Column sibling, not part of this
                      // scroll view, so it never moves with the words.
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // AC-05: the Root's own comment — "最初の言葉".
                            Text(item.comment, style: const TextStyle(fontSize: 17)),
                            const SizedBox(height: 6),
                            Text(
                              formatKotonohaDateTime(item.createdAt),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            if (connectedItems.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Divider(height: 1),
                              ),
                              for (final connection in connectedItems)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(connection.comment, style: const TextStyle(fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text(
                                        formatKotonohaDateTime(connection.createdAt),
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            const SizedBox(height: 16),
                            // Real-device fix: "繋ぐ" now lives here too,
                            // directly on the screen "言の葉をひらく"
                            // actually opens — not only behind the small
                            // photo's undiscoverable tap (see class doc
                            // comment). Same styling, same canConnect
                            // gating, same target screen as
                            // KotonohaDetailScreen's own 繋ぐ button.
                            if (_distanceErrorMessage != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _distanceErrorMessage!,
                                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                                ),
                              ),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4C7A3D),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(0xFF4C7A3D).withValues(alpha: 0.38),
                                  disabledForegroundColor: Colors.white70,
                                ),
                                onPressed: _canConnect ? _onConnectPressed : null,
                                child: const Text('繋ぐ'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallPhoto extends StatelessWidget {
  const _SmallPhoto({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return Container(color: Colors.grey.shade300);
    }
    // Real-device fix: the bottom-right zoom_out_map icon that used to sit
    // over this photo (a "hint" affordance) is removed — tapping the photo
    // still opens KotonohaDetailScreen exactly as before (see the
    // GestureDetector this is wrapped in, in KotonohaWordsScreen.build),
    // only the icon overlay itself is gone.
    return Image.network(
      url,
      // 縦横比を維持したまま縮小する — BoxFit.cover was cropping the
      // photo to fill this header's box; contain only ever shrinks it
      // uniformly, never stretching or cropping (see the class doc
      // comment above).
      fit: BoxFit.contain,
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
          child: Icon(Icons.broken_image, size: 32, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
