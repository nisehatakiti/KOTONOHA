import 'package:flutter/material.dart';

import '../models/kotonoha_root_detail.dart';
import '../utils/kotonoha_format.dart';
import 'leaf_shape.dart';
import 'loading_leaf.dart';

/// What to render inside [KotonohaLeafPopup] (STEP11-UI): a pure
/// presentation state — all the fetching/distance logic that decides
/// which of these applies lives in HomeScreen, never in this widget.
enum KotonohaLeafPopupStatus { loading, notFound, error, loaded }

/// The "opened leaf" shown near a tapped leaf marker (STEP13,
/// docs/map-ui-spec.md section 6) — the small marker itself is hidden by
/// [KotonohaMap] while this is visible (section 6.1), so this widget's own
/// shape has to read as "that same leaf, opened up" rather than a separate
/// speech-bubble window. It shares its silhouette with the map marker via
/// [buildLeafPath]/[LeafClipper] (section 6.2: 葉っぱのシルエットを維持する).
///
/// Content is gated by [isNear] (5m rule, docs section 7): far away, only
/// the Root post's comment and date are shown — no connected comments, no
/// "言の葉をひらく" button at all (not just disabled). Within 5m, the
/// connected comments and the button appear. Photos are never shown here
/// at any distance (section 8) — only [KotonohaDetailScreen], reached via
/// that button, shows the Root's photo.
///
/// This widget never talks to the network itself (HomeScreen/API Service
/// do) and never navigates anywhere itself — [onDetail] is a plain
/// callback the caller wires to whatever navigation it wants.
class KotonohaLeafPopup extends StatelessWidget {
  const KotonohaLeafPopup({
    super.key,
    required this.status,
    this.root,
    this.connectedItems = const [],
    this.isNear = false,
    this.locationUnavailableMessage,
    this.errorMessage,
    this.onRetry,
    this.onDetail,
  });

  final KotonohaLeafPopupStatus status;

  /// The tapped Root post, exactly as the server returned it. Only
  /// meaningful when [status] is `loaded`. Its `imageUrl` is intentionally
  /// never rendered here (docs section 8) — only kept on the model for
  /// [KotonohaDetailScreen] to use.
  final KotonohaRootSummary? root;

  /// The Root's own connect posts, straight from `response.connections`
  /// (STEP11-UI (B) fix: server-side parent_id filtering — never a
  /// client-side spatial guess). Only rendered when [isNear] is true, as
  /// words strung on below the Root's own (docs section 6: 「その場所に
  /// 置かれたRoot投稿と、それに繋がれた言葉の束」).
  final List<KotonohaConnection> connectedItems;

  /// Whether the user is within 5m of [root] — gates the connected-
  /// comments list and the "言の葉をひらく" button (docs section 7).
  /// Defaults to false (far/unknown), matching "安全側に倒す" for the
  /// case where distance couldn't be determined.
  final bool isNear;

  /// Set when the current location couldn't be read at all — shown as an
  /// extra note under the Root comment/date, which are still visible
  /// either way.
  final String? locationUnavailableMessage;

  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onDetail;

  static const _maxConnectedPreview = 3;
  static const _fillColor = Color(0xFFEAF4E4);
  static const _lineColor = Color(0xFF3F7D33);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          painter: const _LeafBackgroundPainter(),
          child: ClipPath(
            clipper: const LeafClipper(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 220,
                maxWidth: 260,
                minHeight: 190,
                maxHeight: 420,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 40, 22, 54),
                child: _buildContent(context),
              ),
            ),
          ),
        ),
        // The stem: a short, separate strip below the leaf body so its own
        // tip — not the leaf body's visual center — is what
        // KotonohaMap's FractionalTranslation(-0.5,-1.0) anchors at the
        // marker's coordinate (docs section 6.2: 「吹き出しの下端が地面側
        // の投稿地点と自然につながる」).
        const CustomPaint(size: Size(6, 14), painter: _StemPainter()),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (status) {
      case KotonohaLeafPopupStatus.loading:
        return const Center(child: LoadingLeaf());

      case KotonohaLeafPopupStatus.notFound:
        return const Center(
          child: Text(
            'この言の葉は見つかりませんでした',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        );

      case KotonohaLeafPopupStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage ?? '読み込みに失敗しました',
              style: const TextStyle(fontSize: 12),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRetry, child: const Text('再試行')),
              ),
            ],
          ],
        );

      case KotonohaLeafPopupStatus.loaded:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final root = this.root;
    if (root == null) {
      // Shouldn't normally happen (HomeScreen maps a missing root to
      // notFound), but never crash on it either way.
      return const Text(
        'この言の葉は見つかりませんでした',
        style: TextStyle(fontSize: 12),
      );
    }

    final children = <Widget>[
      Text(
        root.comment,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 4),
      Text(
        formatKotonohaDateTime(root.createdAt),
        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
      ),
    ];

    if (!isNear) {
      if (locationUnavailableMessage != null) {
        children.addAll([
          const SizedBox(height: 6),
          Text(
            locationUnavailableMessage!,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
          ),
        ]);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    if (connectedItems.isNotEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(height: 1),
      ));
      final preview = connectedItems.take(_maxConnectedPreview);
      for (final item in preview) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              item.comment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      }
      final remaining = connectedItems.length - _maxConnectedPreview;
      if (remaining > 0) {
        children.add(
          Text('ほか$remaining件', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
        );
      }
    }

    children.addAll([
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onDetail,
          child: const Text('言の葉をひらく'),
        ),
      ),
    ]);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _LeafBackgroundPainter extends CustomPainter {
  const _LeafBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildLeafPath(size);
    canvas.drawShadow(path, Colors.black54, 4, false);
    canvas.drawPath(path, Paint()..color = KotonohaLeafPopup._fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = KotonohaLeafPopup._lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StemPainter extends CustomPainter {
  const _StemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = KotonohaLeafPopup._lineColor
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
