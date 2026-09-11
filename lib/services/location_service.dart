import 'package:geolocator/geolocator.dart';

import '../models/location_point.dart';

/// Why [getCurrentLocation] can fail, so the UI can show a specific,
/// actionable message for each case (STEP 4 spec: 権限が許可/未決定/拒否/
/// 永久に拒否, 位置情報サービスOFF must all be handled).
enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

class LocationServiceException implements Exception {
  LocationServiceException(this.reason, [this.message]);

  final LocationFailureReason reason;
  final String? message;
}

/// Shared user-facing message for each [LocationFailureReason], used by any
/// screen that calls [LocationService.getCurrentLocation] (HomeScreen's
/// "地図を更新" and CommentInputScreen's "置く").
String describeLocationFailure(LocationFailureReason reason) {
  switch (reason) {
    case LocationFailureReason.serviceDisabled:
      return '位置情報サービスがOFFになっています。端末の設定でONにしてください。';
    case LocationFailureReason.permissionDenied:
      return '位置情報の権限が許可されていません。権限を許可してもう一度お試しください。';
    case LocationFailureReason.permissionDeniedForever:
      return '位置情報の権限が拒否されています。端末の設定からKOTONOHAの位置情報権限を許可してください。';
    case LocationFailureReason.unknown:
      return '現在地の取得に失敗しました。';
  }
}

/// Separates "get the current device location" from the screens that need
/// it. KOTONOHA never tracks location continuously (docs/concept.md
/// section 7, docs/requirements.md section 6) — this only reads a single
/// position on explicit user action ("地図を更新" / "言の葉を置く"), it
/// does not start any location stream/watch.
class LocationService {
  /// Checks permission/service state, requesting permission if it hasn't
  /// been decided yet, then reads a single high-accuracy position.
  ///
  /// Throws [LocationServiceException] if the location service is off, or
  /// permission is denied/denied forever.
  Future<LocationPoint> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationServiceException(LocationFailureReason.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationServiceException(LocationFailureReason.permissionDenied);
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationServiceException(
        LocationFailureReason.permissionDeniedForever,
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}
