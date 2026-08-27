// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/hydra_api_client.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
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
//   - GET  /api/settings            - full current state, no auth needed
//   - POST /api/settings            - overwrite the whole state,
//     read-modify-write, requires an ADMIN bearer token (an "operator"
//     account gets 403 - see server.ts's own requireAdmin())
//   - POST /api/robot/:id/command   - atomic per-robot command (stop/play/
//     pause/jog/tool/valve/pump/speed/vision), requires a bearer token of
//     EITHER role - the PRIMARY way this app writes (see
//     state/robot_view_model.dart) - small payload, server computes
//     affectedIds (self + combinedWith) itself, persists to disk, and
//     broadcasts a WS "delta" to every other connected client on its own.
//   - GET  /api/system/metrics      - host CPU/memory/temp/uptime/network,
//     no auth needed
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class HydraApiException implements Exception {
  final String message;
  HydraApiException(this.message);
  @override
  String toString() => message;
}

class HydraApiClient {
  final String baseUrl;
  String? authToken;
  final http.Client _client;

  HydraApiClient(String host, int port, {http.Client? client})
      : baseUrl = 'http://$host:$port',
        _client = client ?? http.Client();

  Map<String, String> get _authHeaders =>
      authToken != null ? {'Authorization': 'Bearer $authToken'} : const {};

  /// Self-identifies this client to server.ts's own per-client remote-access
  /// toggles (Config > Remote Access) - lets the project owner disable this
  /// app's own access without also blocking SUITE/Android, or vice versa.
  /// Only GET /api/hydra-info actually checks this header server-side;
  /// sending it on every request is simpler than special-casing just that
  /// one call, and harmless everywhere else.
  static const Map<String, String> _clientHeaders = {'X-Hydra-Client': 'ios'};

  Future<Map<String, dynamic>> login(String username, String password) async {
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

  Future<Map<String, dynamic>?> getHydraInfo() async {
    try {
      final resp = await _client
          .get(Uri.parse('$baseUrl/api/hydra-info'), headers: _clientHeaders)
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

  Future<Map<String, dynamic>> postRobotCommand(dynamic robotId, Map<String, dynamic> payload) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/robot/$robotId/command'),
          headers: {'Content-Type': 'application/json', ..._clientHeaders, ..._authHeaders},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 5));
    return _expectJson(resp);
  }

  Future<Map<String, dynamic>> getSystemMetrics() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/api/system/metrics'), headers: _clientHeaders)
        .timeout(const Duration(seconds: 5));
    return _expectJson(resp);
  }

  Map<String, dynamic> _expectJson(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HydraApiException('HTTP ${resp.statusCode} from ${resp.request?.url.path}');
    }
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw HydraApiException('Response is not valid JSON: ${e.message}');
    }
  }

  void close() => _client.close();
}
