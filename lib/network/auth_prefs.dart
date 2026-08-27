// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/auth_prefs.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Persists the last server (host/port) and session token across app
// launches via shared_preferences, so the user doesn't have to type an IP
// or log back in every time - same "remember me" convenience
// HYDRA-UMC-ANDROID-CONTROL's own network/AuthPrefs.kt + ConnectionPrefs.kt
// provide, merged into one small class here since this app doesn't (yet)
// need the fuller biometric-login profile Android's own version tracks.
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';

class AuthPrefs {
  static const _keyHost = 'hydra_host';
  static const _keyPort = 'hydra_port';
  static const _keyToken = 'hydra_token';
  static const _keyUsername = 'hydra_username';
  static const _keyBiometricEnabled = 'hydra_biometric_enabled';

  Future<void> saveConnection(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, host);
    await prefs.setInt(_keyPort, port);
  }

  Future<(String, int)?> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_keyHost);
    final port = prefs.getInt(_keyPort);
    if (host == null || port == null) return null;
    return (host, port);
  }

  Future<void> saveToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsername, username);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  Future<String?> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
  }

  /// Whether restoring a saved session on launch should be gated behind a
  /// Face ID/Touch ID/Windows Hello prompt first - see
  /// network/biometric_helper.dart and state/robot_view_model.dart's own
  /// init(). Off by default: turning it on is an explicit opt-in from
  /// ui/settings_screen.dart, only ever offered when the device can
  /// actually show a biometric prompt in the first place.
  Future<void> saveBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
  }

  Future<bool> loadBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }
}
