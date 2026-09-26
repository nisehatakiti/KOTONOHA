import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The generated leaf artwork used for the map's small Root-post [Marker]
/// ([createLeafMarkerIcon]).
///
/// 画像アセット置換 (real-device fix): replaces the earlier "standing"
/// leaf silhouette (an upright, almond-shaped leaf whose own stem pointed
/// straight down, cropped from
/// assets/design/a_clean_design_asset_sheet_on_a_transparent_checke.png)
/// with a leaf drawn **lying flat with a soft ground shadow beneath it**
/// (generated fresh — assets/design/a_clean_minimal_studio_style_illustration_on_a_wh.png,
/// trimmed/downsized by tool/process_assets.dart) — matching KOTONOHA's
/// own concept ("言の葉を置く", placing a leaf down) more literally than a
/// leaf that reads as planted/standing upright ever did. [KotonohaLeafPopup]
/// keeps its own separate, dedicated artwork (leaf_popup.png) — this
/// change is the map marker only.
const String kLeafAsset = 'assets/design/leaf_marker.png';

/// [kLeafAsset]'s own pixel dimensions, exactly as processed — used
/// wherever a caller needs to size a display box for it without
/// distorting its proportions.
const double kLeafAssetNativeWidth = 360;
const double kLeafAssetNativeHeight = 333;

/// Loads [kLeafAsset] as a [BitmapDescriptor] for the map's Root-post
/// markers (docs/map-ui-spec.md section 5). No shape is drawn here —
/// [BitmapDescriptor.asset] decodes and scales the PNG itself; this
/// function's only job is picking the on-screen [height] (width follows
/// automatically from the asset's own aspect ratio, so its proportions
/// are never distorted — see [BitmapDescriptor.asset]'s "fitHeight-style"
/// behavior when only one dimension is given).
///
/// [height] defaults a little smaller than the previous artwork's 72
/// (画像アセット置換 real-device fix: "現在の葉っぱマーカーと同程度、また
/// は少し小さいサイズから開始" — start similar-or-slightly-smaller, then
/// adjust for real-device legibility): the earlier standing leaf was
/// *tall* (154x311 — width was already well under its own height), so
/// height=72 kept it visually narrow; this artwork is closer to square
/// (360x333), so the same height=72 would read as noticeably *wider* on
/// the map than the old marker ever did. 60 keeps this new marker's own
/// longest edge similar to the old marker's.
///
/// The [Marker] placing this bitmap must set its own `anchor` explicitly
/// (see kotonoha_map.dart) — the default bottom-center anchor suited the
/// old standing leaf (its stem tip sat at the very bottom of the crop),
/// but this artwork's own "this is the spot" point is the center of the
/// leaf-and-shadow group, not its bottom edge.
Future<BitmapDescriptor> createLeafMarkerIcon(
  BuildContext context, {
  double height = 60,
}) {
  return BitmapDescriptor.asset(
    createLocalImageConfiguration(context),
    kLeafAsset,
    height: height,
  );
}
