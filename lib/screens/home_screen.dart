import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../models/kotonoha_root_detail.dart';
import '../models/location_point.dart';
import '../services/installation_id_service.dart';
import '../services/kotonoha_api_service.dart';
import '../services/location_service.dart';
import '../widgets/ad_banner.dart';
import '../widgets/kotonoha_leaf_popup.dart';
import '../widgets/kotonoha_map.dart';
import 'camera_capture_screen.dart';
import 'kotonoha_words_screen.dart';

/// KOTONOHA's single main screen (docs/ui.md section 1):
/// ad banner, map, and the two primary actions below it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.installationIdService,
    this.locationService,
    this.apiService,
  });

  // Injectable so widget tests can supply fakes instead of hitting real
  // platform plugins; defaults to the real services otherwise.
  final InstallationIdService? installationIdService;
  final LocationService? locationService;
  final KotonohaApiService? apiService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _installationIdService =
      widget.installationIdService ?? InstallationIdService();
  late final _locationService = widget.locationService ?? LocationService();
  late final _apiService = widget.apiService ?? KotonohaApiService();

  LocationPoint? _lastLocation;
  String? _locationErrorMessage;
  bool _isFetchingLocation = false;

  // Real-device fix: lets [_onUpdateMap] call
  // [KotonohaMapState.refreshCurrentLocation] directly — the reliable,
  // explicit replacement for relying on KotonohaMap noticing a changed
  // `currentLocation` constructor value on its own (see that method's own
  // doc comment for the full reasoning).
  final _mapKey = GlobalKey<KotonohaMapState>();

  // Leaf-popup selection state (STEP11-UI): which pin is selected, and
  // what its popup should currently show. HomeScreen owns all of this —
  // KotonohaMap only reports taps and positions whatever popup widget it's
  // given (see KotonohaMap.popupContent).
  String? _selectedId;
  bool _isLoadingSelected = false;
  KotonohaRootSummary? _selectedRoot;
  List<KotonohaConnection> _selectedConnectedItems = const [];
  String? _selectedLocationUnavailableMessage;
  String? _selectedError;
  bool _selectedNotFound = false;

  // The server only ever includes lat/lng/accuracy/image_url when it
  // determined the caller was within 5m (STEP11-UI (A) fix) — their mere
  // presence in the response IS the near/far signal, so there's nothing
  // to recompute client-side (docs section 14: "response.root,
  // response.connectionsをそのまま使用してください").
  bool get _selectedIsNear => _selectedRoot?.latitude != null;

  @override
  void initState() {
    super.initState();
    // installation_id is never shown in the UI (docs/requirements.md
    // section 8); this just ensures it exists from first launch onward so
    // later STEPs can read it via InstallationIdService.
    _installationIdService.getInstallationId();
    // STEP12 section 7 (初回地図表示): a single one-shot location fetch on
    // launch, not a stream — KotonohaMap won't fetch any Root pins at all
    // until _lastLocation is non-null (see its _fetchNearby), so without
    // this the map would stay empty until the user taps "地図を更新".
    _fetchInitialLocation();
  }

  /// The launch-time counterpart to [_onUpdateMap] (STEP12 section 7).
  /// Deliberately doesn't touch [_isFetchingLocation] — that flag only
  /// drives the "地図を更新" button's own spinner, and this isn't a
  /// response to that button being pressed (no new UI, no snackbar either,
  /// per section 7: 既存のローディング状態・地図表示状態を維持する). Errors
  /// still populate [_locationErrorMessage] so the existing debug panel
  /// surfaces them exactly as it would for the button (section 8).
  Future<void> _fetchInitialLocation() async {
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _lastLocation = location;
        _locationErrorMessage = null;
      });
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      setState(() => _locationErrorMessage = describeLocationFailure(e.reason));
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationErrorMessage = '現在地を取得できませんでした。');
    }
  }

  Future<void> _onUpdateMap() async {
    // Real flow (docs/requirements.md section 6, docs/api.md section 3):
    // get current location -> GET /api/kotonoha/nearby -> refresh pins.
    // API call is not implemented yet (STEP 5+); this STEP only wires up
    // the location fetch, taken once per button press (no watch/stream).
    setState(() {
      _isFetchingLocation = true;
      _locationErrorMessage = null;
    });

    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _lastLocation = location;
        _locationErrorMessage = null;
      });
      // Real-device fix: called directly (not left to KotonohaMap's own
      // currentLocation-prop diffing) so "地図を更新" reliably moves the
      // camera, re-fetches nearby pins, and updates the current-location
      // marker every time — see KotonohaMapState.refreshCurrentLocation's
      // own doc comment.
      await _mapKey.currentState?.refreshCurrentLocation(location);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地図を更新しました')),
      );
    } on LocationServiceException catch (e) {
      if (!mounted) return;
      final message = describeLocationFailure(e.reason);
      setState(() => _locationErrorMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  /// Marker tapped (STEP11-UI (A)/(B) fix): get the current location once
  /// (never a stream), then call `GET /api/kotonoha/{id}` with whatever
  /// location was found — the server, not this method, decides the 5m
  /// rule and only includes the Root's photo/connections in the response
  /// when it applies (docs section 5). A location failure still calls the
  /// API (without lat/lng), which the server safely treats as ">5m"; the
  /// Root's comment/date remain visible either way (docs section 13).
  Future<void> _onLeafTap(String id) async {
    setState(() {
      _selectedId = id;
      _isLoadingSelected = true;
      _selectedRoot = null;
      _selectedConnectedItems = const [];
      _selectedLocationUnavailableMessage = null;
      _selectedError = null;
      _selectedNotFound = false;
    });

    LocationPoint? current;
    String? locationUnavailableMessage;
    try {
      current = await _locationService.getCurrentLocation();
    } on LocationServiceException catch (e) {
      locationUnavailableMessage = describeLocationFailure(e.reason);
    } catch (_) {
      locationUnavailableMessage = '現在地を確認できないため、詳細を表示できません。';
    }

    if (!mounted || _selectedId != id) return;

    KotonohaRootDetail detail;
    try {
      detail = await _apiService.fetchKotonohaRootDetail(
        id: int.parse(id),
        latitude: current?.latitude,
        longitude: current?.longitude,
      );
    } on KotonohaApiException catch (e) {
      if (!mounted || _selectedId != id) return;
      setState(() {
        _isLoadingSelected = false;
        if (e.reason == KotonohaApiFailureReason.notFound) {
          _selectedNotFound = true;
        } else {
          _selectedError = e.message;
        }
      });
      return;
    } catch (_) {
      if (!mounted || _selectedId != id) return;
      setState(() {
        _isLoadingSelected = false;
        _selectedError = '読み込みに失敗しました。';
      });
      return;
    }

    if (!mounted || _selectedId != id) return;

    setState(() {
      _isLoadingSelected = false;
      _selectedRoot = detail.root;
      _selectedConnectedItems = detail.connections;
      _selectedLocationUnavailableMessage = locationUnavailableMessage;
    });
  }

  void _retrySelected() {
    final id = _selectedId;
    if (id != null) _onLeafTap(id);
  }

  void _clearSelection() {
    if (_selectedId == null) return;
    setState(() {
      _selectedId = null;
      _isLoadingSelected = false;
      _selectedRoot = null;
      _selectedConnectedItems = const [];
      _selectedLocationUnavailableMessage = null;
      _selectedError = null;
      _selectedNotFound = false;
    });
  }

  Widget? _buildLeafPopup() {
    if (_selectedId == null) return null;

    if (_isLoadingSelected) {
      return const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.loading);
    }
    if (_selectedNotFound) {
      return const KotonohaLeafPopup(status: KotonohaLeafPopupStatus.notFound);
    }
    if (_selectedError != null) {
      return KotonohaLeafPopup(
        status: KotonohaLeafPopupStatus.error,
        errorMessage: _selectedError,
        onRetry: _retrySelected,
      );
    }
    final root = _selectedRoot;
    if (root == null) return null;

    return KotonohaLeafPopup(
      status: KotonohaLeafPopupStatus.loaded,
      root: root,
      connectedItems: _selectedConnectedItems,
      isNear: _selectedIsNear,
      locationUnavailableMessage: _selectedLocationUnavailableMessage,
      onDetail: _selectedIsNear ? () => _openDetail(root) : null,
    );
  }

  Future<void> _openDetail(KotonohaRootSummary root) async {
    // Only ever called when _selectedIsNear (see _buildLeafPopup), so
    // these fields are guaranteed present — the server only omits them
    // when far. KotonohaDetailScreen keeps its existing KotonohaItem-based
    // signature unchanged; no second GET /api/kotonoha/{id} call is made
    // just to open it.
    final item = KotonohaItem(
      id: root.id,
      latitude: root.latitude!,
      longitude: root.longitude!,
      accuracy: root.accuracy!,
      imageUrl: root.imageUrl,
      comment: root.comment,
      createdAt: root.createdAt,
    );
    // Real-device UI pass: "言の葉をひらく" now opens KotonohaWordsScreen
    // first (small fixed photo + scrollable words) rather than jumping
    // straight to the large-photo KotonohaDetailScreen — that screen is
    // now reached one tap deeper, by tapping the small photo there.
    // _selectedConnectedItems is already sitting in state from the same
    // fetch that produced `root`; no extra network call.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KotonohaWordsScreen(
          item: item,
          connectedItems: _selectedConnectedItems,
        ),
      ),
    );
    // Keep the same popup showing after returning (STEP11-UI section 16,
    // recommended option) — a successful connect doesn't change the Root
    // post's own data, and no new map pin is ever added for it.
  }

  void _onPlaceKotonoha() {
    // Full flow (docs/ui.md section 3): re-fetch current location -> update
    // map -> check posting conditions -> open in-app camera -> capture ->
    // confirm -> enter comment (<=50 chars) -> compress -> POST
    // /api/kotonoha. This STEP only implements the camera capture and
    // comment entry UI (CameraCaptureScreen -> CommentInputScreen); the
    // pre-capture location re-fetch and the actual upload are added
    // together with the POST in a later STEP.
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CameraCaptureScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AdBanner(),
            Expanded(
              child: KotonohaMap(
                key: _mapKey,
                currentLocation: _lastLocation,
                onLeafTap: _onLeafTap,
                onMapTap: _clearSelection,
                onSelectionLost: _clearSelection,
                selectedId: _selectedId,
                popupContent: _buildLeafPopup(),
              ),
            ),
            if (_locationErrorMessage != null)
              _LocationDebugPanel(errorMessage: _locationErrorMessage!),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      // Real-device fix: disabled while a leaf popup is open
                      // (_selectedId != null) — pressing either button while
                      // reading the popup made no sense and could move the
                      // map/camera out from under it. The popup's own
                      // close action (tap-outside / onMapTap ->
                      // _clearSelection) is unaffected by this and stays
                      // usable throughout; once it clears, these buttons
                      // re-enable automatically since disabling is derived
                      // straight from _selectedId on every build, not a
                      // separate flag to remember to reset.
                      onPressed: _selectedId != null || _isFetchingLocation
                          ? null
                          : _onUpdateMap,
                      child: _isFetchingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('地図を更新'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedId != null ? null : _onPlaceKotonoha,
                      child: const Text('言の葉を置く'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A location-failure notice (real-device fix: this used to also show a
/// raw "緯度: ... 経度: ... 精度: ...m" readout of the last fetched
/// position whenever one was available — a developer-facing debug value
/// with no place in the production UI, per the latest UI pass. Only the
/// error case remains: a genuine "現在地を取得できませんでした" style
/// failure is still worth surfacing to the user, the same way it already
/// is via the "地図を更新" button's own SnackBar — this is that same
/// message for the one path with no button press to hang a SnackBar off
/// of (the automatic on-launch fetch, [HomeScreen._fetchInitialLocation]).
/// [_lastLocation]/[_locationErrorMessage] themselves, and every use of
/// them elsewhere (map centering, the 3km/5m calculations), are
/// unchanged — only this readout of them is gone.
class _LocationDebugPanel extends StatelessWidget {
  const _LocationDebugPanel({required this.errorMessage});

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        errorMessage,
        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
      ),
    );
  }
}
