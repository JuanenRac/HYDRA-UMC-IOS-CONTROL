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

import 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show ClientPrefsCore;
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_store.dart';

/// The names of the switches kept with [ClientPrefs.loadFlag].
class ClientFlags {
  ClientFlags._();
  static const String deadManJog = 'dead_man_jog';
  static const String linkBlockJog = 'link_block_jog';
  static const String linkIndicator = 'link_indicator';
  static const String pairing = 'pairing';
  static const String watchAlerts = 'watch_alerts';
  static const String presenceRelay = 'presence_relay';
  static const String voiceConfirmRelay = 'voice_confirm_relay';
}

class ClientPrefs extends ClientPrefsCore {
  ClientPrefs() : super(SharedPreferencesPrefsStore());

  static const _keyBlockOnSavedData = 'hydra_block_commands_on_saved_data';
  static const _keySkipMobileVpn = 'hydra_scan_skip_mobile_vpn';
  static const _keyPush = 'hydra_push_notifications';
  static const _keyJobAlerts = 'hydra_job_alerts';
  static const _keyLiveActivity = 'hydra_live_activity';
  static const _keyDictation = 'hydra_dictation';
  static const _keyDictationOnline = 'hydra_dictation_online';
  static const _keyWatch = 'hydra_watch_companion';

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

  /// Whether this phone asks the server for push notifications. Off until the person turns it on: it needs their permission.
  Future<bool> loadPushNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPush) ?? false;
  }

  Future<void> savePushNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPush, value);
  }

  /// Whether the notifications of a job, a robot or the connection are on; [defaultValue] (off in the contract) before any choice.
  Future<bool> loadJobAlerts(bool defaultValue) async => (await SharedPreferences.getInstance()).getBool(_keyJobAlerts) ?? defaultValue;

  Future<void> saveJobAlerts(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyJobAlerts, value);

  /// Whether the Live Activity of the running trajectory is on; off in the contract.
  Future<bool> loadLiveActivity(bool defaultValue) async => (await SharedPreferences.getInstance()).getBool(_keyLiveActivity) ?? defaultValue;

  Future<void> saveLiveActivity(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyLiveActivity, value);

  /// Whether the dictation button of the assistant is shown; off in the contract.
  Future<bool> loadDictation(bool defaultValue) async => (await SharedPreferences.getInstance()).getBool(_keyDictation) ?? defaultValue;

  Future<void> saveDictation(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyDictation, value);

  /// Whether dictation may use the online recognition of Apple when the language has none on the device. Off: the audio never leaves the phone.
  Future<bool> loadDictationOnline() async => (await SharedPreferences.getInstance()).getBool(_keyDictationOnline) ?? false;

  Future<void> saveDictationOnline(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyDictationOnline, value);

  /// Whether the status goes to the Apple Watch and the watch may ask for the global stop; off in the contract.
  Future<bool> loadWatch(bool defaultValue) async => (await SharedPreferences.getInstance()).getBool(_keyWatch) ?? defaultValue;

  Future<void> saveWatch(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyWatch, value);

  /// A switch of this app by its [name] (one of [ClientFlags]); [defaultValue] before any choice. The defaults live in the
  /// command contract, so none is decided here.
  Future<bool> loadFlag(String name, bool defaultValue) async =>
      (await SharedPreferences.getInstance()).getBool('hydra_flag_$name') ?? defaultValue;

  Future<void> saveFlag(String name, bool value) async => (await SharedPreferences.getInstance()).setBool('hydra_flag_$name', value);

}
