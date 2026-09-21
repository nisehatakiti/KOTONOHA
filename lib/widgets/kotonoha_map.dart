import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/kotonoha_pin.dart';
import '../models/location_point.dart';
import '../services/kotonoha_api_service.dart';
import '../utils/distance_utils.dart'
    show kMarkerVisibleRadiusMeters, kNearbyLeafGroupRadiusMeters;
import '../utils/location_bounds_utils.dart';
import 'kotonoha_candidate_sheet.dart';
import 'leaf_marker_icon.dart';

/// Wraps GoogleMap and owns the marker/camera bookkeeping for the main
/// screen (docs/ui.md section 1).
///
/// 言の葉 markers are fetched from `GET /api/kotonoha`, refreshed on
/// camera-idle (STEP8-A) but always scoped to a 3km radius around
/// [currentLocation] — never the map's visible/panned region (STEP12
/// section 6/7). Only Root posts ever appear here — the server already
/// excludes connect posts (STEP11-UI section 10), and Flutter applies its
/// own Haversine filter on top of the server's Bounding Box search to
/// guarantee the 3km circle exactly (STEP12 section 4).
///
/// This widget never starts a location stream/watch of its own, and
/// deliberately does not use GoogleMap's `myLocationEnabled` flag, since
/// that turns on the SDK's own continuous location updates — also unwanted
/// (現在地を継続的に追跡する機能は実装しない, unchanged policy). A single
/// current-location marker ([MarkerId('current_location')], visually
/// distinct from every Root-post leaf marker — a plain default Google Maps
/// pin in a different hue, never the leaf icon) shows where
/// [currentLocation] last was, but it is only ever *updated* by an
/// explicit call ([refreshCurrentLocation], or the very first
/// [currentLocation] this widget ever receives) — never by a stream.
///
/// Real-device fix: "地図を更新" pressed on a real device wasn't
/// reliably moving the camera or refetching nearby pins, and gave no
/// visual indication of where "here" even was. [refreshCurrentLocation]
/// is the fix — a public method HomeScreen calls *directly* via a
/// `GlobalKey<KotonohaMapState>`, rather than relying on this widget
/// noticing a changed [currentLocation] constructor value through
/// [didUpdateWidget]'s own prop-diffing (still used, but now only for the
/// very first location this widget ever receives, at app launch — see
/// that method's own comment). Calling it moves the camera to the new
/// location (panning only — [CameraUpdate.newLatLng] leaves whatever zoom
/// the user already has untouched, so this doesn't reintroduce the
/// "地図を更新でズームが初期値に戻る" bug fixed earlier), re-fetches
/// nearby pins for it, and updates the current-location marker — all
/// synchronously awaitable from the caller, all without any location
/// stream.
///
/// STEP11-UI: this widget's job stops at reporting marker taps and empty-
/// map taps, and positioning whatever [popupContent] the caller hands it
/// near the selected pin — it never fetches pin details or navigates
/// anywhere itself (see HomeScreen for that).
///
/// Real-device fix: when multiple Root pins sit at/near the same spot,
/// which one a tap actually lands on is Google Maps' own hit-testing —
/// not something this app controls, and on-device indistinguishable to
/// the user once two leaf icons visually overlap. A marker's own `onTap`
/// (see [_buildMarkers]) no longer calls [onLeafTap] directly; it first
/// goes through [_handleMarkerTap], which gathers every currently-fetched
/// pin within [kNearbyLeafGroupRadiusMeters] of the tapped one. With only
/// one such pin (itself), behavior is unchanged — [onLeafTap] fires
/// immediately. With more than one, a [KotonohaCandidateSheet] bottom
/// sheet lets the user pick which of them they meant, and [onLeafTap]
/// fires for whichever id they chose. Either way [onLeafTap] still only
/// ever reports a single id — HomeScreen's own fetch/popup flow
/// downstream of it is completely unchanged.
///
/// STEP14 (docs STEP14 section 9/10/11): while [selectedId] is non-null —
/// a leaf popup is open — the map itself becomes inert: no pan, no pinch-
/// zoom, no rotate, no tapping another marker. The map is meant to hold
/// still while "the current leaf" is being read. This is enforced twice,
/// belt-and-suspenders: the `GoogleMap`'s own gesture flags
/// (`scrollGesturesEnabled` etc.) are turned off so the native map SDK
/// never starts a pan/zoom/rotate in the first place, and the whole
/// widget is also wrapped in [IgnorePointer] so no pointer event —
/// including what would otherwise be a marker's own `onTap` — reaches it
/// at all. A transparent full-size layer takes GoogleMap's place for taps
/// while a popup is open: tapping it closes the popup (the same
/// [onMapTap] callback GoogleMap's own `onTap` used when nothing was
/// selected). It sits *below* [popupContent] in the [Stack] but *above*
/// the inert map, so a tap inside the popup's own leaf silhouette is
/// consumed by the popup first (see [KotonohaLeafPopup]'s own
/// `GestureDetector`) and never reaches this closing layer, while a tap
/// anywhere else closes it.
class KotonohaMap extends StatefulWidget {
  const KotonohaMap({
    super.key,
    this.currentLocation,
    this.apiService,
    this.onLeafTap,
    this.onMapTap,
    this.onSelectionLost,
    this.selectedId,
    this.popupContent,
  });

  final LocationPoint? currentLocation;

  // Injectable so widget tests can supply a fake instead of hitting the
  // real network; defaults to the real service otherwise.
  final KotonohaApiService? apiService;

  /// Called with a 言の葉's id when its leaf marker is tapped.
  final void Function(String id)? onLeafTap;

  /// Called when an empty (non-marker) part of the map is tapped —
  /// HomeScreen uses this to close the popup (STEP11-UI section 12/"閉じる
  /// 操作").
  final VoidCallback? onMapTap;

  /// Called when [selectedId] no longer has a known screen position (its
  /// pin fell out of the currently-fetched nearby set, e.g. after panning
  /// far away) — HomeScreen should clear the selection when this fires.
  final VoidCallback? onSelectionLost;

  /// The currently-selected pin's id, if any — used only to position
  /// [popupContent] near that marker. HomeScreen owns what "selected"
  /// means and what the popup shows; this widget just places it.
  final String? selectedId;

  /// Fully-built popup widget (e.g. KotonohaLeafPopup) to overlay near
  /// [selectedId]'s marker. Null means nothing is shown.
  final Widget? popupContent;

  @override
  State<KotonohaMap> createState() => KotonohaMapState();
}

/// Public (not `_`-prefixed) specifically so HomeScreen can hold a
/// `GlobalKey<KotonohaMapState>` and call [refreshCurrentLocation]
/// directly — see that method's own doc comment for why.
class KotonohaMapState extends State<KotonohaMap> {
  /// Shown before the user has ever fetched a real location (STEP5 spec:
  /// 起動直後は固定の適当な初期地点でよい). Roughly Tokyo Station.
  static const _defaultCenter = LatLng(35.681236, 139.767125);

  /// Google Maps has no direct "radius" zoom control; this is a practical
  /// approximation of "現在地周辺約5km程度を見渡せる", not a guaranteed bound.
  static const _regionZoom = 13.0;

  /// Avoids calling the API on every intermediate frame while the user is
  /// still panning/zooming (STEP8-A spec: onCameraIdleで取得し、必要なら
  /// 短いdebounceを入れる).
  static const _fetchDebounce = Duration(milliseconds: 500);

  late final _apiService = widget.apiService ?? KotonohaApiService();

  GoogleMapController? _controller;
  BitmapDescriptor? _leafIcon;
  List<KotonohaPin> _nearbyPins = const [];
  Timer? _debounceTimer;
  Offset? _popupOffset;
  Size? _mapSize;
  bool _leafIconRequested = false;

  /// Drives the current-location marker only — set once on this widget's
  /// very first [KotonohaMap.currentLocation] (app launch) and again on
  /// every [refreshCurrentLocation] call ("地図を更新"). Deliberately a
  /// plain field, not re-derived from [widget.currentLocation] on every
  /// build: HomeScreen's own `_lastLocation` and this field can briefly
  /// disagree mid-update (see [refreshCurrentLocation]), and the marker
  /// should only ever jump when *this widget* has actually processed a
  /// new location, not on every parent rebuild.
  LocationPoint? _displayedCurrentLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Loading the marker's image asset needs an ImageConfiguration (via
    // createLocalImageConfiguration(context)), which relies on
    // InheritedWidgets (MediaQuery etc.) — didChangeDependencies is the
    // point those are guaranteed available, unlike initState. Guarded to
    // run only once; didChangeDependencies can otherwise fire again later
    // (e.g. a theme/locale change) and there's no need to reload the icon
    // then.
    if (!_leafIconRequested) {
      _leafIconRequested = true;
      _loadLeafIcon();
    }
  }

  Future<void> _loadLeafIcon() async {
    final icon = await createLeafMarkerIcon(context);
    if (mounted) setState(() => _leafIcon = icon);
  }

  @override
  void didUpdateWidget(covariant KotonohaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handles *only* the very first location this widget ever receives
    // (app launch, AC-07/AC-10: 初期表示は変更しない) — moves/zooms the
    // camera to the standard region view and does the first nearby
    // fetch, exactly as before. Every later "地図を更新" press no longer
    // goes through this prop-diffing path at all: it's real-device-
    // unreliable (identical()-based change detection, plus Flutter's own
    // rebuild timing, both add indirection between "user pressed the
    // button" and "the map actually reacts") — [refreshCurrentLocation]
    // is the direct, explicit replacement HomeScreen calls instead, via
    // a GlobalKey. This also means a later currentLocation prop change
    // (e.g. if HomeScreen's own state updates for some unrelated reason)
    // no longer silently double-triggers a fetch alongside that explicit
    // call.
    final location = widget.currentLocation;
    if (location != null && oldWidget.currentLocation == null) {
      _displayedCurrentLocation = location;
      _moveCameraToInitialRegion(location);
      _fetchNearby(location);
    }
    if (widget.selectedId != oldWidget.selectedId) {
      _updatePopupPosition();
    }
  }

  /// 「地図を更新」の直接的な実行経路 (real-device fix) — HomeScreenが
  /// `GlobalKey<KotonohaMapState>`経由でこのメソッドを直接呼ぶ。位置情報の
  /// stream/watchは一切使わない — [location]は呼び出し側が
  /// `LocationService.getCurrentLocation()`で一度だけ取得済みの値を渡す。
  ///
  /// 1. 現在地マーカーの表示位置を更新する。
  /// 2. カメラを新しい現在地へ移動する(パンのみ — [CameraUpdate.newLatLng]
  ///    は現在のズームレベルを変更しないため、「地図を更新でズームが
  ///    初期値に戻る」問題を再発させない)。
  /// 3. その現在地を中心にnearby APIを再取得する。
  /// 4. (選択中の言の葉があれば)ポップアップの画面上位置も再計算する。
  Future<void> refreshCurrentLocation(LocationPoint location) async {
    if (mounted) setState(() => _displayedCurrentLocation = location);

    final controller = _controller;
    if (controller != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
      );
    }

    await _fetchNearby(location);
    await _updatePopupPosition();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Moves + zooms the camera to the standard region view around
  /// [location] — used only for the very first location this widget ever
  /// receives (AC-07/AC-10: the initial map display is unchanged). Later
  /// "地図を更新" refreshes deliberately do *not* call this (see
  /// [didUpdateWidget]) so they never reset the user's own zoom/pan.
  Future<void> _moveCameraToInitialRegion(LocationPoint location) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(location.latitude, location.longitude),
        _regionZoom,
      ),
    );
  }

  void _onCameraIdle() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_fetchDebounce, () async {
      await _fetchNearby(widget.currentLocation);
      // The selected pin's on-screen position (or continued existence)
      // may have changed after panning/zooming settles.
      await _updatePopupPosition();
    });
  }

  /// STEP12 3km表示範囲: always queries a Bounding Box centered on
  /// [location] — never the map's visible region — then keeps only the
  /// pins whose true Haversine distance from that location is within
  /// [kMarkerVisibleRadiusMeters] (the Bounding Box alone would let
  /// corner-case pins beyond 3km slip through; see
  /// location_bounds_utils.dart). Panning/zooming the camera doesn't
  /// change what's fetched — only a genuinely new location does, passed
  /// in explicitly by every caller ([onMapCreated]/[_onCameraIdle] pass
  /// [widget.currentLocation] as it currently stands; [didUpdateWidget]'s
  /// initial-arrival branch and [refreshCurrentLocation] pass the
  /// specific location they each just received) — this method itself no
  /// longer reads [widget.currentLocation] on its own, so there is never
  /// any ambiguity about which location a given fetch used.
  ///
  /// With no known location, 3km can't be determined at all, so this is a
  /// no-op rather than falling back to some other range (STEP12 section 8:
  /// 現在地不明時は安全側としてRoot投稿を新規取得しない) — including on the
  /// very first call from [onMapCreated], before HomeScreen's initial
  /// location fetch has resolved.
  Future<void> _fetchNearby(LocationPoint? location) async {
    final controller = _controller;
    if (controller == null || location == null) return;

    try {
      final box = computeBoundingBox(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );
      final pins = await _apiService.fetchNearby(
        north: box.north,
        south: box.south,
        east: box.east,
        west: box.west,
      );
      final withinRadius = filterPinsWithinRadius(
        pins: pins,
        centerLatitude: location.latitude,
        centerLongitude: location.longitude,
        radiusMeters: kMarkerVisibleRadiusMeters,
      );
      if (mounted) setState(() => _nearbyPins = withinRadius);
    } catch (_) {
      // A failed nearby-fetch must never crash the map or block the
      // current-location feature; keep whatever pins are already shown
      // (docs: 一覧取得失敗を毎回ダイアログ表示する必要はない).
    }
  }

  /// Recomputes where [widget.popupContent] should sit on screen, given
  /// [widget.selectedId]'s marker position. Closes the popup (via
  /// [KotonohaMap.onSelectionLost]) if that pin isn't part of the
  /// currently-known nearby set, or its screen position has moved outside
  /// the map's own bounds (STEP11-UI section 12, option A: "対象ピンが
  /// 画面外に出たら閉じる").
  Future<void> _updatePopupPosition() async {
    final controller = _controller;
    final selectedId = widget.selectedId;
    if (controller == null || selectedId == null) {
      if (mounted && _popupOffset != null) setState(() => _popupOffset = null);
      return;
    }

    KotonohaPin? pin;
    for (final p in _nearbyPins) {
      if (p.id == selectedId) {
        pin = p;
        break;
      }
    }
    if (pin == null) {
      if (mounted) setState(() => _popupOffset = null);
      widget.onSelectionLost?.call();
      return;
    }

    final screenCoordinate = await controller.getScreenCoordinate(
      LatLng(pin.latitude, pin.longitude),
    );
    if (!mounted) return;

    final ratio = MediaQuery.of(context).devicePixelRatio;
    final rawOffset = Offset(
      screenCoordinate.x / ratio,
      screenCoordinate.y / ratio,
    );

    final size = _mapSize;
    final margin = 24.0;
    final isOutOfView =
        size == null ||
        rawOffset.dx < -margin ||
        rawOffset.dy < -margin ||
        rawOffset.dx > size.width + margin ||
        rawOffset.dy > size.height + margin;

    if (isOutOfView) {
      setState(() => _popupOffset = null);
      widget.onSelectionLost?.call();
      return;
    }

    setState(() => _popupOffset = _clampPopupAnchor(rawOffset, size));
  }

  /// STEP14 section 7/8: [KotonohaLeafPopup] renders upward and centered
  /// from whatever point it's anchored at, so a marker sitting right at
  /// the very top/left/right of the map could otherwise push the popup's
  /// own top or sides off the screen even though the marker itself is
  /// still "in view" by [_updatePopupPosition]'s own out-of-view check.
  /// This nudges the anchor just enough to give a normal-sized popup room
  /// — not a full smart-placement system (deliberately not attempting to
  /// flip the popup below the marker or resize it to fit): in the common
  /// case (marker away from the edges) this returns [raw] unchanged, and
  /// the stem still points at the exact marker pixel. Only right at an
  /// edge does the anchor — and so the stem's tip — shift slightly inward
  /// to keep the leaf itself fully on-screen.
  Offset _clampPopupAnchor(Offset raw, Size mapSize) {
    // Real-device fix (AC-06): this used to be 190 — sized for an earlier,
    // shorter popup design. KotonohaLeafPopup's current leaf_popup.png
    // window is itself up to ~450px tall once its short stem is included
    // (280 wide × ~434 tall body, per its own _width/_height, plus the
    // stem strip below it) when fully loaded with connections — with the
    // old 190 margin, the popup's own *top* (where its date/time sits)
    // could be clamped to extend above this map widget's own visible
    // area entirely, landing right up against — or past — the AdBanner
    // that sits directly above the map in HomeScreen's Column (there is
    // no gap between them to lose). Sized here to the popup's own real
    // worst-case height plus a real breathing-room buffer, so the date
    // always clears the ad by an actual margin instead of barely
    // avoiding this widget's own top edge.
    const topSafeMargin = 480.0;
    const sideSafeMargin = 130.0; // roughly half the popup's fixed width

    final maxDx = mapSize.width - sideSafeMargin;
    final dx = maxDx < sideSafeMargin
        ? mapSize.width / 2
        : raw.dx.clamp(sideSafeMargin, maxDx);
    final dy = raw.dy < topSafeMargin ? topSafeMargin : raw.dy;

    return Offset(dx, dy);
  }

  /// A leaf marker was tapped: [tapped] is whichever pin Google Maps' own
  /// hit-testing resolved the tap to. Finds every other currently-fetched
  /// pin within [kNearbyLeafGroupRadiusMeters] of it (via the same
  /// [filterPinsWithinRadius] helper the 3km nearby-fetch filter already
  /// uses) and, only when that group has more than one member, opens a
  /// [KotonohaCandidateSheet] for the user to disambiguate — with exactly
  /// one member (the common case), this is a no-op wrapper and
  /// [widget.onLeafTap] fires immediately, unchanged from before this
  /// existed.
  Future<void> _handleMarkerTap(KotonohaPin tapped) async {
    final candidates = filterPinsWithinRadius(
      pins: _nearbyPins,
      centerLatitude: tapped.latitude,
      centerLongitude: tapped.longitude,
      radiusMeters: kNearbyLeafGroupRadiusMeters,
    );

    if (candidates.length <= 1) {
      widget.onLeafTap?.call(tapped.id);
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => KotonohaCandidateSheet(
        candidateIds: [for (final pin in candidates) pin.id],
        apiService: _apiService,
      ),
    );
    if (!mounted || selectedId == null) return;

    widget.onLeafTap?.call(selectedId);
  }

  /// Root-post leaf markers, plus the current-location marker (real-device
  /// fix — see [refreshCurrentLocation]'s own comment for why one exists
  /// now). The selected pin (if any) is skipped entirely while its leaf
  /// is open, rather than drawn underneath it (section 6.1: 小さいピンと
  /// 大きい吹き出し葉っぱを同時に表示してはならない) — reappearing the
  /// moment the selection clears.
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    for (final pin in _nearbyPins) {
      if (pin.id == widget.selectedId) continue;
      markers.add(
        Marker(
          markerId: MarkerId(pin.id),
          position: LatLng(pin.latitude, pin.longitude),
          icon:
              _leafIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          // didUpdateWidget picks up the resulting selectedId change (once
          // HomeScreen's setState propagates back down) and positions the
          // popup then — calling _updatePopupPosition() here directly
          // would still see the *old* widget.selectedId.
          onTap: () => _handleMarkerTap(pin),
        ),
      );
    }

    final currentLocationMarker = _buildCurrentLocationMarker();
    if (currentLocationMarker != null) markers.add(currentLocationMarker);

    return markers;
  }

  /// 現在地マーカー — Root投稿の葉っぱマーカー([_leafIcon]、カスタム画像)
  /// とは明確に区別するため、既定のGoogle Mapsピン(ただし葉っぱとは異なる
  /// 色相)をそのまま使う。新しいアイコン画像アセットは追加しない。
  /// [KotonohaMap.onLeafTap]的なタップ処理は持たない(言の葉ではないので
  /// [_handleMarkerTap]の対象にならない) — 位置を示すだけの存在。
  Marker? _buildCurrentLocationMarker() {
    final location = _displayedCurrentLocation;
    if (location == null) return null;

    return Marker(
      markerId: const MarkerId('current_location'),
      position: LatLng(location.latitude, location.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.currentLocation;
    final initialCenter = location == null
        ? _defaultCenter
        : LatLng(location.latitude, location.longitude);
    // STEP14 section 9: a leaf popup is open — hold the map still.
    final isLeafOpen = widget.selectedId != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        _mapSize = constraints.biggest;
        return Stack(
          children: [
            IgnorePointer(
              // Blocks every pointer event from reaching GoogleMap while a
              // leaf is open — including what would otherwise be a
              // different marker's own onTap (STEP14 section 9: 「地図上
              // の別Markerタップ禁止」), belt-and-suspenders alongside the
              // gesture flags below.
              ignoring: isLeafOpen,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialCenter,
                  zoom: _regionZoom,
                ),
                onMapCreated: (controller) {
                  _controller = controller;
                  _fetchNearby(widget.currentLocation);
                },
                onCameraIdle: _onCameraIdle,
                onTap: (_) => widget.onMapTap?.call(),
                markers: _buildMarkers(),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                // STEP14 section 9: disables pan/pinch-zoom/rotate/tilt at
                // the native map SDK level while a leaf is open, rather
                // than relying solely on IgnorePointer above (which some
                // platform-view embeddings can bypass for raw touches).
                scrollGesturesEnabled: !isLeafOpen,
                zoomGesturesEnabled: !isLeafOpen,
                rotateGesturesEnabled: !isLeafOpen,
                tiltGesturesEnabled: !isLeafOpen,
              ),
            ),
            if (isLeafOpen)
              // STEP14 section 10/11: takes GoogleMap's tap-to-close job
              // while a leaf is open (GoogleMap itself can't receive taps
              // under IgnorePointer above). Sits below popupContent in
              // this Stack, so a tap inside the popup's own leaf shape is
              // consumed there first (see KotonohaLeafPopup's
              // GestureDetector) and never reaches this layer — only a
              // tap genuinely outside the popup closes it, and doing so
              // only clears the current selection, never selects a new
              // marker (KotonohaMap.onMapTap, not onLeafTap).
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('kotonoha-map-tap-to-close'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onMapTap?.call(),
                ),
              ),
            if (_popupOffset != null && widget.popupContent != null)
              Positioned(
                left: _popupOffset!.dx,
                top: _popupOffset!.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -1.0),
                  child: widget.popupContent,
                ),
              ),
          ],
        );
      },
    );
  }
}
