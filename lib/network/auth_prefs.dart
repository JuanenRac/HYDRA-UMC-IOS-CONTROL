// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/auth_prefs.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Persists the last server (host/port) across app launches via
// shared_preferences - not secrets, so a plain preferences file is the right
// store for them - and the session (token, user name, refresh token).
//
// The session rules (secure storage only, a failed save reverts what it wrote,
// a renewal keeps the refresh token and a sign-in replaces it, the logged-out
// marker is set before the secure delete, a legacy plain token is moved in)
// are the ones every mobile app shares: they live in `SessionStore` of the
// shared Dart package (see the SDK's docs/SESSION_STORE.md) and are checked
// against its conformance vectors. This file only supplies the platform's
// storage: `flutter_secure_storage` (real Keychain on iOS, DPAPI-backed encrypted storage on Windows) and
// shared_preferences for the plain markers.
// =============================================================================

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hydra_umc_app_common/hydra_umc_app_common.dart';

import 'shared_preferences_store.dart';
import 'strong_session_backend.dart';

// Tests inject a fake of this seam instead of a real platform channel.
export 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show SecureTokenBackend;

class FlutterSecureStorageBackend implements SecureTokenBackend {
  // Items are readable only after the first unlock and never leave this
  // device (no iCloud Keychain sync, no migration to another phone through a
  // backup): the session belongs to this installation.
  FlutterSecureStorageBackend([FlutterSecureStorage? storage])
    : _storage = storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  /// The Keychain items behind the strong biometric mode: their access control is the currently enrolled biometrics (Face ID or
  /// Touch ID), so reading one makes the system show the prompt. They use their own service name, apart from the normal items.
  FlutterSecureStorageBackend.biometric()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accountName: 'hydra_strong_session',
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The plain markers of the session, kept in ordinary shared preferences.

/// The last server and the session of this app. The preferences and the session rules are the shared ones of the SDK
/// package (clients/dart_app_common); this class gives them the platform's storage.
class AuthPrefs extends AuthPrefsCore {
  AuthPrefs({SecureTokenBackend? secureBackend, SecureTokenBackend? strongBackend})
      : this._(secureBackend ?? FlutterSecureStorageBackend(), strongBackend ?? FlutterSecureStorageBackend.biometric(), SharedPreferencesPrefsStore());

  AuthPrefs._(SecureTokenBackend normal, SecureTokenBackend strong, SharedPreferencesPrefsStore plain)
      : this._routed(
          StrongSessionBackend(
            normal: normal,
            strong: strong,
            isStrong: () async => (await plain.getBool(strongSessionFlagKey)) ?? false,
          ),
          plain,
        );

  AuthPrefs._routed(StrongSessionBackend backend, SharedPreferencesPrefsStore plain)
      : _backend = backend,
        _plain = plain,
        super(store: plain, session: SessionStore(secure: backend, plain: plain, log: debugPrint));

  final StrongSessionBackend _backend;
  final SharedPreferencesPrefsStore _plain;

  /// Whether the session is kept behind the biometric prompt (the strong mode; off by default).
  Future<bool> loadBiometricStrong() async => (await _plain.getBool(strongSessionFlagKey)) ?? false;

  /// Turns the strong mode on or off, moving the stored session between the two stores. Throws, with nothing changed, when the
  /// device refuses the protected item (no passcode set, no biometrics enrolled).
  Future<void> setBiometricStrong(bool value) => _backend.switchTo(value, (strong) => _plain.setBool(strongSessionFlagKey, strong));
}
