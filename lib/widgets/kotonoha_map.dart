import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/kotonoha_pin.dart';
import '../models/location_point.dart';
import '../services/kotonoha_api_service.dart';
import '../utils/distance_utils.dart' show kMarkerVisibleRadiusMeters;
import '../utils/location_bounds_utils.dart';
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
/// The camera itself only moves when a new [currentLocation] is supplied;
/// this widget never starts a location stream of its own, and deliberately
/// does not use GoogleMap's `myLocationEnabled` flag, since that turns on
/// the SDK's own continuous location updates — also unwanted per STEP13
/// (docs/map-ui-spec.md section 4: 現在地を追跡する機能は実装しない). No
/// marker of any kind is drawn for [currentLocation] itself (STEP13
/// section 11): "地図を更新" still moves the camera there, but nothing
/// visually marks the spot — Root leaves are the only thing meant to draw
/// the eye (section 15: 「Root投稿の葉っぱ > 地図」).
///
/// STEP11-UI: this widget's job stops at reporting marker taps and empty-
/// map taps, and positioning whatever [popupContent] the caller hands it
/// near the selected pin — it never fetches pin details or navigates
/// anywhere itself (see HomeScreen for that).
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
  State<KotonohaMap> createState() => _KotonohaMapState();
}

class _KotonohaMapState extends State<KotonohaMap> {
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

  @override
  void initState() {
    super.initState();
    _loadLeafIcon();
  }

  Future<void> _loadLeafIcon() async {
    final icon = await createLeafMarkerIcon();
    if (mounted) setState(() => _leafIcon = icon);
  }

  @override
  void didUpdateWidget(covariant KotonohaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final location = widget.currentLocation;
    if (location != null && !identical(location, oldWidget.currentLocation)) {
      _moveCameraTo(location);
    }
    if (widget.selectedId != oldWidget.selectedId) {
      _updatePopupPosition();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _moveCameraTo(LocationPoint location) async {
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
      await _fetchNearby();
      // The selected pin's on-screen position (or continued existence)
      // may have changed after panning/zooming settles.
      await _updatePopupPosition();
    });
  }

  /// STEP12 3km表示範囲: always queries a Bounding Box centered on
  /// [widget.currentLocation] — never the map's visible region — then
  /// keeps only the pins whose true Haversine distance from that location
  /// is within [kMarkerVisibleRadiusMeters] (the Bounding Box alone would
  /// let corner-case pins beyond 3km slip through; see
  /// location_bounds_utils.dart). Panning/zooming the camera doesn't change
  /// what's fetched — only a new [widget.currentLocation] does.
  ///
  /// With no known location, 3km can't be determined at all, so this is a
  /// no-op rather than falling back to some other range (STEP12 section 8:
  /// 現在地不明時は安全側としてRoot投稿を新規取得しない) — including on the
  /// very first call from [onMapCreated], before HomeScreen's initial
  /// location fetch has resolved.
  Future<void> _fetchNearby() async {
    final controller = _controller;
    final location = widget.currentLocation;
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
    final offset = Offset(
      screenCoordinate.x / ratio,
      screenCoordinate.y / ratio,
    );

    final size = _mapSize;
    final margin = 24.0;
    final isOutOfView =
        size == null ||
        offset.dx < -margin ||
        offset.dy < -margin ||
        offset.dx > size.width + margin ||
        offset.dy > size.height + margin;

    if (isOutOfView) {
      setState(() => _popupOffset = null);
      widget.onSelectionLost?.call();
      return;
    }

    setState(() => _popupOffset = offset);
  }

  /// Root-post leaf markers only (docs/map-ui-spec.md section 4: 現在地は
  /// 地図上で重要な視覚要素として扱わない — no current-location marker of
  /// our own is drawn at all; "地図を更新" still focuses the camera there,
  /// but nothing marks the spot). The selected pin (if any) is skipped
  /// entirely while its leaf is open, rather than drawn underneath it
  /// (section 6.1: 小さいピンと大きい吹き出し葉っぱを同時に表示しては
  /// ならない) — reappearing the moment the selection clears.
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
          onTap: () => widget.onLeafTap?.call(pin.id),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.currentLocation;
    final initialCenter = location == null
        ? _defaultCenter
        : LatLng(location.latitude, location.longitude);

    return LayoutBuilder(
      builder: (context, constraints) {
        _mapSize = constraints.biggest;
        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialCenter,
                zoom: _regionZoom,
              ),
              onMapCreated: (controller) {
                _controller = controller;
                _fetchNearby();
              },
              onCameraIdle: _onCameraIdle,
              onTap: (_) => widget.onMapTap?.call(),
              markers: _buildMarkers(),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
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
