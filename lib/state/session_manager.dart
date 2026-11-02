// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/session_manager.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The one place that decides what an expired session does to a request: it is
// renewed once (callers that arrive while a renewal runs share its result) and
// the request is repeated once; any other answer, or a failed renewal, reaches
// the caller as it came. It holds no widget and no ChangeNotifier, so it is
// tested without the view model. How a renewal is done (the refresh token, the
// stored session) stays with the owner of the session, which passes it in.
// =============================================================================

import 'dart:async';

import '../network/hydra_api_client.dart';

/// Renews the session and says whether it worked (never throws).
typedef SessionRenewal = Future<bool> Function();

class SessionManager {
  SessionManager({required this.client, required this.renew});

  /// The client of the live session (null while signed out).
  final HydraApiClient? Function() client;

  /// How a renewal is done; it belongs to the owner of the session.
  final SessionRenewal renew;
  Future<bool>? _inFlight;

  /// True while a renewal is running.
  bool get renewing => _inFlight != null;

  /// The single entry to renewing the session: callers that arrive while a
  /// renewal is running share its result instead of starting their own.
  Future<bool> renewSession() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final renewal = renew().whenComplete(() => _inFlight = null);
    _inFlight = renewal;
    return renewal;
  }

  /// Runs [call] with the session's token. An expired or invalid token (a 403
  /// TOKEN_EXPIRED / TOKEN_INVALID, or a 401) renews the session once and
  /// repeats the call; any other answer, or a failed renewal, reaches the
  /// caller as it came.
  Future<T> authed<T>(Future<T> Function(HydraApiClient client) call) async {
    final current = client();
    if (current == null) throw HydraApiException('Not connected');
    try {
      return await call(current);
    } on HydraApiException catch (e) {
      if (!e.isSessionProblem) rethrow;
      if (!await renewSession()) rethrow;
      return await call(client() ?? current);
    }
  }
}
