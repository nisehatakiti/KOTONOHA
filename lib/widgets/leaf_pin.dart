import 'package:flutter/material.dart';

/// Leaf-shaped pin used to mark a 言の葉 on the map (docs/ui.md section 4,
/// docs/requirements.md: "ピンは葉っぱ型").
///
/// Content (photo/comment) is intentionally not shown here — pins only
/// reveal that a 言の葉 exists until the viewer is within 10m.
class LeafPin extends StatelessWidget {
  const LeafPin({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.eco,
      color: Color(0xFF4C7A3D),
      size: 28,
      shadows: [Shadow(color: Colors.black26, blurRadius: 3)],
    );
  }
}
