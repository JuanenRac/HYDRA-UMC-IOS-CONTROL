// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/client_prefs.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Two opt-in safety/privacy switches the operator controls from the app.
// Both default to off, which is how the app behaved before they existed.
//   - blockCommandsOnSavedData: do not send commands while the screen shows
//     the saved copy of the robot state instead of the live one (STOP is
//     never blocked).
//   - skipMobileAndVpnNetworks: the subnet scan leaves out the mobile-data
//     and VPN interfaces of the phone.
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';

class ClientPrefs {
  static const _keyBlockOnSavedData = 'hydra_block_commands_on_saved_data';
  static const _keySkipMobileVpn = 'hydra_scan_skip_mobile_vpn';

  Future<bool> loadBlockCommandsOnSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBlockOnSavedData) ?? false;
  }

  Future<void> saveBlockCommandsOnSavedData(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBlockOnSavedData, value);
  }

  Future<bool> loadSkipMobileAndVpnNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySkipMobileVpn) ?? false;
  }

  Future<void> saveSkipMobileAndVpnNetworks(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipMobileVpn, value);
  }
}
