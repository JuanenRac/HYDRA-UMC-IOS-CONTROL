// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/shortcut_bridge.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The global stop asked for from outside the app: the Shortcuts app, Siri, the
// Action button and the quick action of the app icon (ios/Runner/
// GlobalStopShortcut.swift). The native half only leaves a request, which waits
// at most one minute; the stop itself is the one the STOP button already makes
// (POST /api/stop-all with the session of the person), so nothing else is
// trusted or sent by the shortcut.
// =============================================================================

import 'package:flutter/services.dart';

abstract class ShortcutBridge {
  /// True once when a request of a system shortcut is waiting (and young enough).
  Future<bool> takeGlobalStop();

  /// Called when a request arrives while the app is already running.
  void onGlobalStopRequested(void Function() callback);
}

class MethodChannelShortcutBridge implements ShortcutBridge {
  static const MethodChannel _channel = MethodChannel('hydra_umc/shortcuts');

  @override
  Future<bool> takeGlobalStop() async {
    try {
      return await _channel.invokeMethod<bool>('takeGlobalStop') ?? false;
    } on MissingPluginException {
      return false; // not running on iOS (tests, desktop)
    } on PlatformException {
      return false;
    } catch (_) {
      return false; // no bindings (a plain unit test)
    }
  }

  @override
  void onGlobalStopRequested(void Function() callback) {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'globalStopRequested') callback();
      });
    } catch (_) {
      // no bindings (a plain unit test): nothing can call back
    }
  }
}
