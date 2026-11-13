// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/strong_session_backend.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The strong biometric mode (off by default; port of the Android option). The app keeps a session, not a password, so the
// mode moves the stored session (token, user name, refresh token) to a Keychain item whose access control is the currently
// enrolled biometrics: the system itself asks for Face ID or Touch ID to read it, so the secret can not be read by an app
// that only fakes a "success", and a face or finger enrolled later invalidates it (sign in again). iOS has no weak
// biometric class, so no sign-in method is lost when the mode is on.
// =============================================================================

import 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show SecureTokenBackend, SessionKeys;

/// The plain-preferences key that says the session is in the biometric Keychain item.
const String strongSessionFlagKey = 'hydra_biometric_strong';

/// Routes the session items to the normal store or, while the strong mode is on, to the one behind the biometric prompt.
/// In the strong mode a value read once is kept for the run, so one prompt covers the renewals that follow.
class StrongSessionBackend implements SecureTokenBackend {
  StrongSessionBackend({required this._normal, required this._strong, required this._isStrong});

  final SecureTokenBackend _normal;
  final SecureTokenBackend _strong;
  final Future<bool> Function() _isStrong;
  final Map<String, String> _cache = {};

  static const List<String> _keys = [SessionKeys.token, SessionKeys.username, SessionKeys.refreshToken];

  @override
  Future<void> write(String key, String value) async {
    if (await _isStrong()) {
      await _strong.write(key, value);
      _cache[key] = value;
    } else {
      await _normal.write(key, value);
    }
  }

  @override
  Future<String?> read(String key) async {
    if (!await _isStrong()) return _normal.read(key);
    final cached = _cache[key];
    if (cached != null) return cached;
    final value = await _strong.read(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  @override
  Future<void> delete(String key) async {
    _cache.remove(key);
    if (await _isStrong()) {
      await _strong.delete(key);
    } else {
      await _normal.delete(key);
    }
  }

  /// Moves the session to the strong store ([strong] true) or back, then calls [setFlag] with the new mode and erases the
  /// old copy. Anything thrown while copying leaves the mode and the old copy as they were.
  Future<void> switchTo(bool strong, Future<void> Function(bool strong) setFlag) async {
    final from = strong ? _normal : _strong;
    final to = strong ? _strong : _normal;
    final moved = <String, String>{};
    for (final key in _keys) {
      final value = await from.read(key);
      if (value != null) moved[key] = value;
    }
    for (final entry in moved.entries) {
      await to.write(entry.key, entry.value);
    }
    await setFlag(strong);
    _cache
      ..clear()
      ..addAll(strong ? moved : const {});
    for (final key in _keys) {
      try {
        await from.delete(key);
      } catch (_) {
        // The mode already changed; a copy that could not be erased is only ever read again if the mode is switched back.
      }
    }
  }
}
