// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/state_cache.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Persistent cache of the last known settings tree (HydraState.raw, the shape of the server payload), so the Dashboard and the
// Control screen show the saved robots at once on launch instead of an empty state while connect() is still running. The live
// connect() replaces it as soon as it succeeds; the cache is a stop-gap for the offline or reconnecting window, never a source
// of truth.
//
// loadCachedState() returns the save instant with the data, so the caller can tell how old what is on screen is (isStale, as in
// the last-known-state cache of the watch app). A cache without a timestamp is treated as maximally stale.
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
  static const _keyScope = 'hydra_last_state_scope';

  /// The key a copy belongs to: the account and the server it was read from, so that the copy of one server or
  /// account is never shown as the state of another.
  static String scopeOf(String host, int port, String username) => '$username@$host:$port';

  /// Keys of the settings tree that hold credentials and never go to disk.
  static const _secretKeys = {'ipUsername', 'ipPassword'};

  /// [value] without any secret key at any depth, as a copy.
  static dynamic redactSecrets(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_secretKeys.contains(entry.key)) entry.key: redactSecrets(entry.value),
      };
    }
    if (value is List) return value.map(redactSecrets).toList();
    return value;
  }

  /// Erases the saved copy (a sign-out: it belongs to that session).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastState);
    await prefs.remove(_keySavedAtMs);
    await prefs.remove(_keyScope);
  }

  Future<void> saveState(Map<String, dynamic> raw, {String? scope}) async {
    final prefs = await SharedPreferences.getInstance();
    if (scope == null) {
      await prefs.remove(_keyScope);
    } else {
      await prefs.setString(_keyScope, scope);
    }
    await prefs.setString(_keyLastState, jsonEncode(redactSecrets(raw)));
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

  /// Like [loadState] (null on first launch or a corrupt cache), plus the instant it was saved. A cache with no recorded
  /// timestamp reports [CachedState.savedAt] as `DateTime.fromMillisecondsSinceEpoch(0)`: an unknown age is maximally stale, never
  /// "just saved".
  /// launch or a corrupt cache), but also carries the real save instant -
  /// see this file's own header note. A cache saved by an older app
  /// build with no recorded timestamp (an in-place update from before
  /// this field existed) reports [CachedState.savedAt] as
  /// `DateTime.fromMillisecondsSinceEpoch(0)` - unknown age is treated as
  /// maximally stale, never as "just saved", the same fail-closed
  /// convention used elsewhere in this ecosystem for an unknown state.
  ///
  /// With a [scope], a copy saved for another scope (or with none, as an older build did) is not returned: it is
  /// erased, because it belongs to a server or an account that is not the one being opened.
  Future<CachedState?> loadCachedState({String? scope}) async {
    final raw = await loadState();
    if (raw == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (scope != null && prefs.getString(_keyScope) != scope) {
      await clear();
      return null;
    }
    final savedAtMs = prefs.getInt(_keySavedAtMs) ?? 0;
    return CachedState(raw: raw, savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs));
  }
}
