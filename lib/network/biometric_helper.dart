// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/biometric_helper.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Thin wrapper over package:local_auth, playing the same role
// HYDRA-UMC-ANDROID-CONTROL's own util/BiometricHelper.kt plays there:
// isAvailable() gates whether settings_screen.dart even offers the toggle,
// authenticate() shows the native Face ID/Touch ID/Windows Hello prompt.
// Adapted to this app's own architecture rather than a literal port:
// Android's version gates re-entering a remembered username/password (this
// app never stores a raw password at all, only a bearer token - see
// auth_prefs.dart), so here it gates restoring an already-valid saved
// session on launch instead (see state/robot_view_model.dart's own
// init()/unlockWithBiometrics()) - same "reforzar el login" goal from
// mejoras_futuras.txt, adapted to what this app actually persists.
// biometricOnly: true mirrors Android's BIOMETRIC_STRONG|BIOMETRIC_WEAK
// (no device-credential/passcode fallback allowed) as closely as
// local_auth's own cross-platform API allows.
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
