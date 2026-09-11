import 'package:flutter/material.dart';

import 'leaf_shape.dart';

/// A quiet, leaf-motif loading indicator (STEP13, docs/map-ui-spec.md
/// section 11) — replaces the old "距離を確認しています…" text. The leaf
/// itself sways gently while its distance/detail is being resolved,
/// instead of a generic spinner or a sentence narrating the process.
///
/// A single lightweight [AnimationController] drives a small rotation and
/// scale wobble (「軽い回転」「わずかな揺れ」, docs section 11/12) — never a
/// full spin, and never anything that keeps demanding attention. It stops
/// naturally when this widget leaves the tree (i.e. as soon as the caller
/// swaps [KotonohaLeafPopupStatus.loading] for a real result).
class LoadingLeaf extends StatefulWidget {
  const LoadingLeaf({super.key, this.size = 40});

  final double size;

  @override
  State<LoadingLeaf> createState() => _LoadingLeafState();
}

class _LoadingLeafState extends State<LoadingLeaf>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Transform.rotate(
          // A light sway (±~5°), not a spin.
          angle: (t - 0.5) * 0.18,
          child: Transform.scale(scale: 0.94 + (t * 0.1), child: child),
        );
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size * 1.3,
        child: CustomPaint(painter: _SmallLeafPainter()),
      ),
    );
  }
}

class _SmallLeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = buildLeafPath(size);
    canvas.drawPath(path, Paint()..color = const Color(0xFF6FAA5B));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF3F7D33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
