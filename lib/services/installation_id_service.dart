import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provides the app's anonymous `installation_id`.
///
/// KOTONOHA has no user accounts (docs/concept.md, docs/requirements.md
/// section 8): instead each install is identified by a random ID that is
/// generated once, persisted on-device, and reused for the lifetime of the
/// install. It is never shown in the UI and is only meant to be sent to the
/// API in later STEPs.
class InstallationIdService {
  InstallationIdService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _prefsKey = 'installation_id';

  final Uuid _uuid;
  String? _cachedId;

  /// Returns the persisted installation_id, generating and storing a new
  /// one on first launch.
  Future<String> getInstallationId() async {
    final cached = _cachedId;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null) {
      _cachedId = existing;
      return existing;
    }

    final generated = _uuid.v4();
    await prefs.setString(_prefsKey, generated);
    _cachedId = generated;
    return generated;
  }
}
