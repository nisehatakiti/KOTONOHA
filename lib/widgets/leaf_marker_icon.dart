import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The generated leaf artwork used for every leaf surface in KOTONOHA —
/// the map's small Root-post [Marker] ([createLeafMarkerIcon]) and the
/// expanded [KotonohaLeafPopup] background both use this exact file, just
/// displayed at different sizes.
///
/// Image-asset pass: this is a pixel crop, taken verbatim (no redraw, no
/// recolor, no reshaping) from the generated design sheet
/// assets/design/a_clean_design_asset_sheet_on_a_transparent_checke.png —
/// specifically its "マーカー（通常）" cell, with the surrounding label
/// text excluded by the crop. It is the *only* cell in that sheet that is
/// both leaf-only (no sample text baked in) and free of the sheet's map
/// background, which is why the popup reuses it too rather than the
/// sheet's own dedicated "ポップアップ" cells (see
/// kotonoha_leaf_popup.dart's doc comment for why those weren't usable as
/// a live background).
const String kLeafAsset = 'assets/design/leaf_marker.png';

/// [kLeafAsset]'s own pixel dimensions, exactly as cropped — used
/// wherever a caller needs to size a display box for it without
/// distorting its proportions (e.g. [KotonohaLeafPopup]).
const double kLeafAssetNativeWidth = 154;
const double kLeafAssetNativeHeight = 311;

/// Loads [kLeafAsset] as a [BitmapDescriptor] for the map's Root-post
/// markers (docs/map-ui-spec.md section 5). No shape is drawn here —
/// [BitmapDescriptor.asset] decodes and scales the PNG itself; this
/// function's only job is picking the on-screen [height] (width follows
/// automatically from the asset's own aspect ratio, so its proportions
/// are never distorted — see [BitmapDescriptor.asset]'s "fitHeight-style"
/// behavior when only one dimension is given).
///
/// [Marker] anchors a bitmap at its bottom-center by default, which is
/// also where this artwork's own stem tip sits (the stem is baked into
/// the artwork itself, not drawn separately), so that's what ends up
/// marking the coordinate — no extra anchor configuration needed.
Future<BitmapDescriptor> createLeafMarkerIcon(
  BuildContext context, {
  double height = 72,
}) {
  return BitmapDescriptor.asset(
    createLocalImageConfiguration(context),
    kLeafAsset,
    height: height,
  );
}
