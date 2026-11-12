// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/biometric_helper.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Thin wrapper over package:local_auth. isAvailable() decides whether settings_screen.dart offers the toggle; authenticate()
// shows the native Face ID, Touch ID or Windows Hello prompt, with biometricOnly: true (no passcode fallback).
// The app stores a bearer token and never a password, so the gate protects the restore of an already valid saved session on
// launch (see init() and unlockWithBiometrics() in state/robot_view_model.dart).
// =============================================================================

import 'package:local_auth/local_auth.dart';

class BiometricHelper {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device can plausibly show a biometric prompt at all -
  /// checked once at startup (see RobotViewModel.init()) so the settings
  /// toggle and the unlock gate don't offer something that will just fail.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      // Any platform-channel failure (plugin not registered for this
      // build, permission missing, ...) means "can't offer this",
      // not "crash the app over an optional convenience feature".
      return false;
    }
  }

  /// Shows the native prompt; true only on real success - cancellation,
  /// failure, and any plugin-level error all come back false rather than
  /// throwing, since every caller here treats "not unlocked" uniformly
  /// regardless of why.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      // local_auth 3.x throws LocalAuthException for anything beyond a
      // plain failed/cancelled attempt (which already returns false above)
      // - every caller here treats "not unlocked" uniformly regardless of
      // why, so there's nothing more useful to do with the exception than
      // fold it into the same false result.
      return false;
    }
  }
}
