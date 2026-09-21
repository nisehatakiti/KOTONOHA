import 'package:flutter/material.dart';

/// Shared KOTONOHA-leaf-motif background for detail-style screens (real-
/// device fix, originally added to KotonohaDetailScreen): a pale green
/// wash plus the same generated leaf artwork already used elsewhere in the
/// app (assets/design/leaf_popup.png), shown very faint and peeking in
/// from a corner rather than filling the screen, so it never competes with
/// whatever [child] this wraps. No shape is drawn in code here — [Opacity]
/// + [Positioned] is the only styling applied to the image itself.
///
/// Extracted out of KotonohaDetailScreen so KotonohaWordsScreen's small-
/// photo screen can use the exact same background rather than a new one
/// (spec: 「新しい別デザインを作る必要はない」) — both screens' visual
/// output is unchanged by this extraction.
class LeafDecoratedSection extends StatelessWidget {
  const LeafDecoratedSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

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
            right: -46,
            top: -36,
            child: Opacity(
              opacity: 0.10,
              child: Image.asset(
                'assets/design/leaf_popup.png',
                width: 214,
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
