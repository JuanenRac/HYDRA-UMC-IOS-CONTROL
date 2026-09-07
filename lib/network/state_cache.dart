// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/state_cache.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Ported from HYDRA-UMC-ANDROID-CONTROL's own network/StateCache.kt: a
// persistent cache of the last known settings tree (models/hydra_state.dart's
// own HydraState.raw - the exact same shape the server's own WS/REST
// payload already uses, so no separate serialization schema to keep in
// sync), so the Dashboard/Control screens show real, if possibly stale,
// robot data immediately on launch instead of an empty state while the
// live connect() round-trip is still in flight - genuinely useful on a
// phone that just came back into WiFi range. Superseded by the real
// connect() the moment it succeeds; this cache exists purely for that
// brief offline/reconnecting window, not as a source of truth.
// =============================================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StateCache {
  static const _keyLastState = 'hydra_last_state';

  Future<void> saveState(Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastState, jsonEncode(raw));
  }

  /// Returns null on first launch (nothing cached yet) or if the cached
  /// JSON is somehow corrupt - never throws, since a broken cache must
  /// never block the app from starting.
  Future<Map<String, dynamic>?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyLastState);
    if (jsonStr == null) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
