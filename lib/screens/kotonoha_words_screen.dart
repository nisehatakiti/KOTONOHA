import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../models/kotonoha_root_detail.dart';
import '../services/location_service.dart';
import '../utils/kotonoha_format.dart';
import '../widgets/ad_banner.dart';
import '../widgets/leaf_decorated_section.dart';
import 'kotonoha_detail_screen.dart';

/// The screen reached via "言の葉をひらく" (real-device UI pass) — a
/// compact "words" view: [item]'s own photo shown small and pinned at the
/// top, with its comment ("最初の言葉") and every one of [connectedItems]
/// listed below it in a scrollable area. Tapping the small photo is what
/// leads to the *previous* "言の葉をひらく" destination —
/// [KotonohaDetailScreen], entirely unchanged — now reached one tap
/// deeper rather than being the immediate destination itself: 「現在の画
/// 面を『写真タップ後の状態』として利用する」— this screen is new, but
/// KotonohaDetailScreen itself was not rewritten to build it.
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
class KotonohaWordsScreen extends StatelessWidget {
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

  /// Forwarded to [KotonohaDetailScreen] when the photo is tapped —
  /// injectable so widget tests can supply a fake instead of hitting real
  /// platform plugins; defaults to the real service otherwise (the same
  /// pattern KotonohaDetailScreen itself already uses).
  final LocationService? locationService;

  Future<void> _openPhoto(BuildContext context) async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KotonohaDetailScreen(item: item, locationService: locationService),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
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
        ),
        // A quiet affordance hinting the small photo expands on tap.
        Positioned(
          right: 8,
          bottom: 8,
          child: Icon(
            Icons.zoom_out_map,
            color: Colors.white.withValues(alpha: 0.9),
            size: 20,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}
