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
//
// I07: this class used to save/load the raw tree with no timestamp at
// all - exactly the plain "visual cache" the original idea warned
// against, with no way for a caller to know whether what's on screen is
// five seconds or five days old if a real reconnect never happens (a
// dead server, a wrong host after a device restore, ...). loadCachedState()
// now returns that real save instant alongside the data, mirroring
// HYDRA-UMC-WATCH's own real LastKnownStateCache.kt (staleAfterMs/isStale)
// - the same real risk, the same real fix, ported to this persistent
// (not in-memory) cache.
// =============================================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One cached settings tree plus the real wall-clock instant it was saved.
class CachedState {
  final Map<String, dynamic> raw;
  final DateTime savedAt;

  const CachedState({required this.raw, required this.savedAt});

  /// How long ago [savedAt] was, relative to [now] (defaults to the real
  /// current time). Never negative even if the device clock moved
  /// backward since the save, so a caller never displays a bogus
  /// negative age.
  Duration age({DateTime? now}) {
    final delta = (now ?? DateTime.now()).difference(savedAt);
    return delta.isNegative ? Duration.zero : delta;
  }
}

class StateCache {
  static const _keyLastState = 'hydra_last_state';
  static const _keySavedAtMs = 'hydra_last_state_saved_at_ms';

  Future<void> saveState(Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastState, jsonEncode(raw));
    await prefs.setInt(_keySavedAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns null on first launch (nothing cached yet) or if the cached
  /// JSON is somehow corrupt - never throws, since a broken cache must
  /// never block the app from starting. Kept alongside [loadCachedState]
  /// for callers that only ever needed the raw tree.
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

  /// Same real success/failure contract as [loadState] (null on first
  /// launch or a corrupt cache), but also carries the real save instant -
  /// see this file's own I07 header note. A cache saved by an older app
  /// build with no recorded timestamp (an in-place update from before
  /// this field existed) reports [CachedState.savedAt] as
  /// `DateTime.fromMillisecondsSinceEpoch(0)` - unknown age is treated as
  /// maximally stale, never as "just saved", the same fail-closed
  /// convention used elsewhere in this ecosystem for an unknown state.
  Future<CachedState?> loadCachedState() async {
    final raw = await loadState();
    if (raw == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final savedAtMs = prefs.getInt(_keySavedAtMs) ?? 0;
    return CachedState(raw: raw, savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs));
  }
}
