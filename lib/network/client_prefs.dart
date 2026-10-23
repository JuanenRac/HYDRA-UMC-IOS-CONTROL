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
  static const _keyControllerId = 'hydra_controller_id';

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

  /// The controller id kept for this installation, or null before the first one was saved.
  Future<String?> loadControllerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyControllerId);
  }

  /// Keeps the controller id, so a reservation made from this device can still
  /// be released after the app restarts.
  Future<void> saveControllerId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyControllerId, id);
  }
}
