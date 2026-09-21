import 'dart:async';

import 'package:flutter/material.dart';

/// A quiet, leaf-motif loading indicator (STEP13, docs/map-ui-spec.md
/// section 11) — replaces the old "距離を確認しています…" text.
///
/// Image-asset pass: this used to be a [CustomPainter] animating a
/// generated leaf [Path] with [Transform.rotate]/[Transform.scale]. It
/// now instead cycles through three generated frames — pixel crops taken
/// verbatim from the design sheet
/// assets/design/a_clean_design_asset_sheet_on_a_transparent_checke.png
/// (its "ローディング（1/2/3コマ目）" cells), each already drawn with its
/// own small "swoosh" motion marks — rather than this widget drawing or
/// animating a leaf shape itself. Cycling 1→2→3→2→1→… (a simple ping-pong
/// through the three frames) reproduces the same restrained, repeating
/// sway the old rotate/scale animation had (「軽い回転」「わずかな揺れ」,
/// docs section 11/12), just via frame-swapping instead of a transform.
/// It stops naturally when this widget leaves the tree (i.e. as soon as
/// the caller swaps [KotonohaLeafPopupStatus.loading] for a real result).
class LoadingLeaf extends StatefulWidget {
  const LoadingLeaf({super.key, this.height = 52});

  final double height;

  @override
  State<LoadingLeaf> createState() => _LoadingLeafState();
}

class _LoadingLeafState extends State<LoadingLeaf> {
  static const _frameAssets = [
    'assets/design/leaf_loading_1.png',
    'assets/design/leaf_loading_2.png',
    'assets/design/leaf_loading_3.png',
  ];
  static const _frameDuration = Duration(milliseconds: 260);

  Timer? _timer;
  int _frameIndex = 0;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_frameDuration, (_) => _advanceFrame());
  }

  void _advanceFrame() {
    if (!mounted) return;
    setState(() {
      _frameIndex += _direction;
      if (_frameIndex >= _frameAssets.length - 1 || _frameIndex <= 0) {
        _direction = -_direction;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(_frameAssets[_frameIndex], height: widget.height);
  }
}
