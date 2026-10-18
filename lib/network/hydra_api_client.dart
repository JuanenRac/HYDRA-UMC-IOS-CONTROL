// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/hydra_api_client.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Talks the exact contract in HYDRA-UMC-SERVER/docs/REMOTE_API.md - the
// headless backend split out of HYDRA-UMC STUDIO's own process (STUDIO is
// now a pure frontend client of this same server, not a server itself).
// That document itself admits it can drift from server.ts, the real source
// of truth - worth verifying against the server's own code rather than
// trusting the doc blindly):
//   - POST /api/login               - obtain a bearer token. Real multi-user
//     accounts (server.ts's own users.ts) - every server seeds a default
//     admin/admin account on its own first-ever start, and can have
//     additional lower-privilege "operator" accounts created from
//     Config > Users in the browser UI.
//   - GET  /api/hydra-info          - discovery/identity, 404 if this app's
//     own access has been disabled server-side (Config > Remote Access,
//     per-client, identified via the X-Hydra-Client: ios header every
//     request below carries)
//   - GET  /api/settings            - full current state, needs a bearer token (either role)
//   - POST /api/settings            - overwrite the whole state,
//     read-modify-write, requires an ADMIN bearer token (an "operator"
//     account gets 403 - see server.ts's own requireAdmin())
//   - POST /api/stop-all            - global stop of every robot
//   - POST /api/robot/:id/command   - atomic per-robot command (stop/play/
//     pause/jog/tool/valve/pump/speed/vision), requires a bearer token of
//     EITHER role - the PRIMARY way this app writes (see
//     state/robot_view_model.dart) - small payload, server computes
//     affectedIds (self + combinedWith) itself, persists to disk, and
//     broadcasts a WS "delta" to every other connected client on its own.
//   - GET  /api/system/metrics      - host CPU/memory/temp/uptime/network,
//     no auth needed unless the server runs with HYDRA_UMC_INFO_AUTH=required
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/assistant_reply.dart';

class HydraApiException implements Exception {
  final String message;
  /// HTTP status of the server's answer; null when there was no answer.
  final int? statusCode;
  /// The stable `code` field of the server's JSON error body
  /// (TOKEN_EXPIRED, TOKEN_INVALID, SESSION_REVOKED, ...), when it sent one.
  final String? code;
  /// The server's own `error` text, when it sent one.
  final String? serverMessage;
  HydraApiException(this.message, {this.statusCode, this.code, this.serverMessage});

  /// A 401, or a 403 that says the token expired or is invalid: a refresh or
  /// a new login can cure it. (A plain 403 is a missing role permission.)
  bool get isSessionProblem =>
      statusCode == 401 || (statusCode == 403 && (code == 'TOKEN_EXPIRED' || code == 'TOKEN_INVALID'));

  /// A 403 about the account's role, not about the session.
  bool get isPermissionDenied => statusCode == 403 && !isSessionProblem;

  /// The robot is reserved by another account (the server's 409).
  bool get isReservedByAnother => statusCode == 409;

  /// The server refused the command itself (unknown command, a value it cannot take).
  bool get isRejectedCommand => statusCode == 400;

  /// Over the server's rate limit (429).
  bool get isRateLimited => statusCode == 429;

  /// The server does not have the route (an older server).
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

class HydraApiClient {
  // Starts as plain HTTP - getHydraInfo() below switches it to HTTPS the
  // first time a plain-HTTP probe gets no answer at all and an HTTPS one
  // does (server.ts's own optional TLS_CERT_PATH/TLS_KEY_PATH switches a
  // server to HTTPS/WSS-only, no HTTP fallback of its own). Mirrors
  // HYDRA-UMC-ANDROID-CONTROL's own HydraApiClient.baseUrl/usesTls -
  // same real fix, same reasoning, independently implemented per client.
  String baseUrl;
  bool get usesTls => baseUrl.startsWith('https://');
  String? authToken;
  final http.Client _client;

  /// [useTls] starts the client on https:// - for a server that was already
  /// seen answering TLS. It never goes back to plain http by itself: a server
  /// that once spoke TLS and now answers over http is not trusted with a
  /// password or a token in the clear.
  HydraApiClient(String host, int port, {http.Client? client, bool useTls = false})
      : baseUrl = '${useTls ? 'https' : 'http'}://$host:$port',
        _client = client ?? http.Client();

  Map<String, String> get _authHeaders =>
      authToken != null ? {'Authorization': 'Bearer $authToken'} : const {};

  /// Headers for requests made outside this class (the live camera stream):
  /// the client identity and the bearer token. A server started with
  /// HYDRA_UMC_CAMERA_AUTH=required refuses the picture without a signed-in
  /// client; the token goes in a header, never in the address.
  Map<String, String> get mediaHeaders => {..._clientHeaders, ..._authHeaders};

  /// Self-identifies this client to server.ts's own per-client remote-access
  /// toggles (Config > Remote Access) - lets the project owner disable this
  /// app's own access without also blocking SUITE/Android, or vice versa.
  /// Only GET /api/hydra-info actually checks this header server-side;
  /// sending it on every request is simpler than special-casing just that
  /// one call, and harmless everywhere else.
  static const Map<String, String> _clientHeaders = {'X-Hydra-Client': 'ios'};

  Future<Map<String, dynamic>> login(String username, String password) async {
    // login() is this app's own real FIRST request against a fresh host
    // (see this method's own timeout comment) - unlike getHydraInfo(),
    // which discovery.dart always calls before ever reaching here, a
    // direct "add server, log in" flow never gets a chance to learn the
    // real scheme first. Resolve it here too, before spending the login
    // attempt itself on a scheme that a TLS-only server won't answer.
    await _resolveScheme();
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/login'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders},
          body: jsonEncode({'username': username, 'password': password}),
        )
        // Longer than the other calls' 5s (see _expectJson's own callers
        // below): login is the very first request against a host, so
        // unlike a request over an already-warm connection it also pays
        // for DNS resolution and TCP/connection setup - both of which can
        // run considerably slower than 5s on a real industrial LAN (managed
        // switches, slow local DNS, a server just waking up) even though
        // the server itself would have answered in time.
        .timeout(const Duration(seconds: 15));
    return _expectJson(resp);
  }

  /// exchanges a still-valid refresh token (returned alongside the
  /// access token by login() above - see HYDRA-UMC-SERVER's own
  /// refresh_tokens.ts / REMOTE_API.md section 2a) for a fresh access
  /// token, no password involved: this app never stores one (auth_prefs.dart's
  /// own header comment on why only the token itself lives in secure
  /// storage). Throws on a 401 (the session was genuinely revoked, or the
  /// refresh token itself expired/unknown) - it is the caller's job, not
  /// this method's, to decide that means falling back to a real logout.
  /// Mirrors HYDRA-UMC-DSI's own copy of this method.
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/refresh'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 5));
    return _expectJson(resp);
  }

  /// revokes a refresh token server-side on a real, intentional
  /// logout - best-effort by design (the caller clears its own local state
  /// regardless; see robot_view_model.dart's own logout()). Never throws -
  /// a network error here must not block a local sign-out the user is
  /// actively waiting on.
  Future<void> logoutRemote(String refreshToken) async {
    try {
      await _client
          .post(
            Uri.parse('$baseUrl/api/logout'),
            headers: {'Content-Type': 'application/json', ..._clientHeaders},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort - see this method's own doc comment.
    }
  }

  Future<Map<String, dynamic>?> getHydraInfo() async {
    final direct = await _probeHydraInfo(baseUrl);
    if (direct != null) return direct;
    // A server with TLS_CERT_PATH/TLS_KEY_PATH set answers nothing
    // sensible to plain HTTP - retry once over HTTPS before giving up,
    // and remember it via baseUrl for every later call through this same
    // client. Never the other way around: a plain-HTTP server that fails
    // is just offline, not a reason to guess at HTTPS.
    if (baseUrl.startsWith('http://')) {
      final httpsUrl = baseUrl.replaceFirst('http://', 'https://');
      final viaHttps = await _probeHydraInfo(httpsUrl);
      if (viaHttps != null) {
        baseUrl = httpsUrl;
        return viaHttps;
      }
    }
    return null;
  }

  /// Same scheme-resolution getHydraInfo() does, reused by login() - a
  /// real GET /api/hydra-info probe (harmless, needs no credentials) just
  /// to learn which scheme this host actually answers on, discarding the
  /// payload itself since the caller here only cares about baseUrl.
  Future<void> _resolveScheme() async {
    if (baseUrl.startsWith('https://')) return;
    if (await _probeHydraInfo(baseUrl) != null) return;
    final httpsUrl = baseUrl.replaceFirst('http://', 'https://');
    if (await _probeHydraInfo(httpsUrl) != null) baseUrl = httpsUrl;
  }

  /// One real probe of GET {base}/api/hydra-info, never throwing - see
  /// getHydraInfo()'s own comment for why this exists as its own method.
  Future<Map<String, dynamic>?> _probeHydraInfo(String base) async {
    try {
      final resp = await _client
          .get(Uri.parse('$base/api/hydra-info'), headers: _clientHeaders)
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!json.containsKey('remoteApiVersion')) return null;
      return json;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getSettings() async {
    // The other real entry point besides login() - RobotViewModel.connect()
    // calls this directly for a restored session (a saved host/port with
    // no fresh login step), which otherwise never resolves the scheme at
    // all. See _resolveScheme()'s own doc comment.
    await _resolveScheme();
    final resp = await _client
        .get(Uri.parse('$baseUrl/api/settings'), headers: {..._clientHeaders, ..._authHeaders})
        .timeout(const Duration(seconds: 5));
    return _expectJson(resp);
  }

  Future<void> postSettings(Map<String, dynamic> payload) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/settings'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders, ..._authHeaders},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 5));
    _expectJson(resp);
  }

  /// [timeout] is 5 s for an ordinary command; a STOP uses a shorter one so a
  /// stuck connection is given up and retried quickly.
  Future<Map<String, dynamic>> postRobotCommand(
    dynamic robotId,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/robot/$robotId/command'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders, ..._authHeaders},
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    return _expectJson(resp);
  }

  /// POST /api/stop-all: the global stop. No body, no confirmation; any
  /// signed-in account may call it and a reservation held by another account
  /// never blocks it. Answers `{success, stoppedCount, failedCount, persisted,
  /// robots: [...]}`. A short [timeout] so a stuck connection is given up and
  /// the caller can try again at once. A server that does not have the route
  /// answers 404 and one over its rate limit answers 429 (both are
  /// [HydraApiException]s the caller turns into the per-robot stop).
  Future<Map<String, dynamic>> postStopAll({Duration timeout = const Duration(seconds: 2)}) async {
    final resp = await _client
        .post(Uri.parse('$baseUrl/api/stop-all'), headers: {..._clientHeaders, ..._authHeaders})
        .timeout(timeout);
    return _expectJson(resp);
  }

  /// Sends a typed/recognised voice turn to HYDRA-UMC-VOICE-UI (via Server's
  /// POST /api/voice/turn, same route HYDRA-UMC-ANDROID-CONTROL's own
  /// in-app voice button and paired-Watch relay both use) and returns the
  /// assistant's reply. requestId/locale generated here rather than left to
  /// the caller, matching how ANDROID-CONTROL's own postVoiceTurn() callers
  /// build theirs - one less thing for a UI widget to get right.
  Future<AssistantReply> postVoiceTurn(String transcript, String locale) async {
    final requestId = 'ios-${DateTime.now().millisecondsSinceEpoch}';
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/voice/turn'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders, ..._authHeaders},
          body: jsonEncode({
            'type': 'voice_turn',
            'requestId': requestId,
            'transcript': transcript,
            'locale': locale,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return AssistantReply.fromJson(_expectJson(resp));
  }

  Future<Map<String, dynamic>> getSystemMetrics() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/api/system/metrics'), headers: {..._clientHeaders, ..._authHeaders})
        .timeout(const Duration(seconds: 5));
    return _expectJson(resp);
  }

  Map<String, dynamic> _expectJson(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // The server's error body carries a reason (`error`) and, for the auth
      // middleware, a stable `code`: keep both so the caller can tell an
      // expired session from a missing permission, an unknown command (400)
      // or a robot reserved by someone else (409).
      String? code;
      String? serverMessage;
      try {
        final body = jsonDecode(resp.body);
        if (body is Map) {
          if (body['code'] is String) code = body['code'] as String;
          if (body['error'] is String) serverMessage = body['error'] as String;
        }
      } catch (_) {
        // Not JSON (a proxy's HTML page, say): the status alone has to do.
      }
      throw HydraApiException(
        'HTTP ${resp.statusCode} from ${resp.request?.url.path}',
        statusCode: resp.statusCode,
        code: code,
        serverMessage: serverMessage,
      );
    }
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw HydraApiException('Response is not valid JSON: ${e.message}');
    }
  }

  void close() => _client.close();
}
