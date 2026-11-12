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
//     accounts (the server's users.ts): the operator always supplies the
//     credentials, no account is assumed. A production server has no
//     built-in account - its first administrator comes from the
//     HYDRA_UMC_BOOTSTRAP_ADMIN_* settings - and lower-privilege "operator"
//     accounts are created from Config > Users in the browser UI.
//   - GET  /api/hydra-info          - discovery/identity, 404 if this app's
//     own access has been disabled server-side (Config > Remote Access,
//     per-client, identified via the X-Hydra-Client: ios header every
//     request below carries)
//   - GET  /api/settings            - full current state, needs a bearer token (either role)
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


import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show HydraApiCore, HydraApiException;

import '../app_version.dart';
import '../models/access.dart';
import '../models/contract_v2.dart';
import '../models/assistant_reply.dart';
import '../models/ecosystem.dart';
import '../models/robot_command_contract.dart';
import '../util/connection_diagnostics.dart' show InfoProbe;
import 'command_sequence.dart';
import 'package_http_transport.dart';
import 'tls_settings.dart';

// The refused-answer type, the numbering of motion commands, the renewal of an
// expired session and the headers live in the shared package of the SDK
// (clients/dart_app_common); this class adds the choice between http and https
// (the TLS policy of the app) and the endpoints that answer with the app's own models.
export 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show HydraApiException, TokenRenewer;

class HydraApiClient extends HydraApiCore {
  // Starts as plain HTTP; getHydraInfo() switches to HTTPS the first time a plain probe gets no answer and an HTTPS one does
  // (a server with TLS_CERT_PATH and TLS_KEY_PATH answers HTTPS and WSS only, with no HTTP fallback).
  /// True once this server was seen answering over TLS (or was saved so).
  bool _tlsSeen;

  /// The controller id of this installation (see models/access.dart), sent in
  /// the body and in the `X-Controller-Id` header of every reserve, release,
  /// jog-arm and command. It is made once and kept (see ClientPrefs), so a
  /// reservation made from this device can still be released after a restart.
  static String controllerId = generateControllerId();

  /// [useTls] starts the client on https:// - for a server that was already
  /// seen answering TLS. It never goes back to plain http by itself: a server
  /// that once spoke TLS and now answers over http is not trusted with a
  /// password or a token in the clear.
  HydraApiClient(String host, int port, {http.Client? client, bool useTls = false})
      : _tlsSeen = useTls,
        super(
          baseUrl: '${useTls || !TlsPolicy.isLoopback(host) ? 'https' : 'http'}://$host:$port',
          transport: PackageHttpTransport(client ?? createClient()),
          clientHeader: clientHeaderValue(kAppVersion),
          controllerIdOf: () => controllerId,
          sequence: CommandSequence.shared,
        );

  /// `ios/<version>`, or just `ios` when the version is not one the server
  /// takes (1 to 24 of 0-9 A-Z a-z . _ -). Self-identifies this client to the
  /// server's per-client remote-access toggles (Config > Remote Access).
  static String clientHeaderValue(String version) => HydraApiCore.clientHeaderValue('ios', version);

  Future<Map<String, dynamic>?> getHydraInfo() async {
    final direct = await _probeHydraInfo(baseUrl);
    if (direct != null) {
      _noteSchemeWorks();
      return direct;
    }
    // HTTPS is tried first. Plain HTTP is only a second try, and only when
    // the person allowed it in the security settings (and the server is on
    // the local network unless they allowed remote plain traffic too). A
    // server that once spoke TLS is never retried over plain HTTP.
    final other = _otherSchemeUrl();
    if (other != null) {
      final viaOther = await _probeHydraInfo(other);
      if (viaOther != null) {
        baseUrl = other;
        _noteSchemeWorks();
        return viaOther;
      }
    }
    return null;
  }

  /// Same scheme-resolution getHydraInfo() does, reused by login() - a
  /// real GET /api/hydra-info probe (harmless, needs no credentials) just
  /// to learn which scheme this host actually answers on, discarding the
  /// payload itself since the caller here only cares about baseUrl.
  @override
  Future<void> resolveScheme() async {
    if (usesTls && _tlsSeen) return;
    _httpsProbeError = null;
    if (await _probeHydraInfo(baseUrl) != null) {
      _noteSchemeWorks();
      return;
    }
    final other = _otherSchemeUrl();
    if (other == null) return;
    if (await _probeHydraInfo(other) != null) {
      baseUrl = other;
      _noteSchemeWorks();
    } else if (usesTls && _httpsProbeError != null && isTlsFailure(_httpsProbeError!) && !isCertificateRejection(_httpsProbeError!)) {
      // The server does not speak TLS at all (it ended the handshake, it did not refuse a certificate) and plain HTTP
      // is allowed for this host: the server just does not answer GET /api/hydra-info, so go by the failed handshake.
      baseUrl = other;
    }
  }

  Object? _httpsProbeError;

  /// A server that answered over HTTPS is not trusted over plain HTTP later.
  void _noteSchemeWorks() {
    if (usesTls) _tlsSeen = true;
  }

  /// The other scheme to try for this host, or null when it must not be tried:
  /// plain HTTP only if allowed for this host and TLS was never seen to work.
  String? _otherSchemeUrl() {
    if (baseUrl.startsWith('http://')) return baseUrl.replaceFirst('http://', 'https://');
    if (_tlsSeen) return null;
    final host = Uri.parse(baseUrl).host;
    if (!TlsSettingsStore.current.plainAllowedFor(host)) return null;
    return baseUrl.replaceFirst('https://', 'http://');
  }

  /// One real probe of GET {base}/api/hydra-info, never throwing - see
  /// getHydraInfo()'s own comment for why this exists as its own method.
  Future<Map<String, dynamic>?> _probeHydraInfo(String base) async {
    try {
      final resp = await call('GET', '$base/api/hydra-info', headers: clientHeaders, timeout: const Duration(seconds: 3));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!json.containsKey('remoteApiVersion')) return null;
      return json;
    } catch (e) {
      if (base.startsWith('https://')) _httpsProbeError = e;
      return null;
    }
  }

  Future<List<ClaimInfo>> getClaims() async =>
      ClaimInfo.listFromJson(await getJson('/api/claims', const Duration(seconds: 5)));

  Future<RobotRead?> getRobot(dynamic robotId) async {
    try {
      final answer = await getJson('/api/robot/$robotId', const Duration(seconds: 5));
      final robot = answer['robot'];
      if (robot is! Map<String, dynamic>) return null;
      return RobotRead(robot, revisionOf(answer));
    } on HydraApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// The audit lines of the server ([query] is the part after `/api/audit`).
  Future<String> getAuditBody(String query) => getText('/api/audit$query', const Duration(seconds: 10));

  Future<String> getConnectionClientsBody() => getText('/api/connections/clients', const Duration(seconds: 10));

  Future<String> getConnectionEventsBody(int limit) =>
      getText('/api/connections/events?limit=${limit.clamp(1, 500)}', const Duration(seconds: 10));

  Future<String> getServerConfigBody() => getText('/api/admin/server-config', const Duration(seconds: 10));

  Future<String> putServerConfigBody(String json) async {
    final resp = await call('PUT', '$baseUrl/api/admin/server-config',
        headers: {'Content-Type': 'application/json', ...clientHeaders, ...authHeaders},
        body: json,
        timeout: const Duration(seconds: 10));
    throwForStatus(resp);
    return resp.body;
  }

  Future<void> postPushDevice(String token, String locale) async {
    final resp = await post('/api/push/devices', const Duration(seconds: 10), {'token': token, 'platform': 'ios', 'locale': locale});
    throwForStatus(resp);
  }

  /// Hands the token of a Live Activity to the server, which then refreshes the card through the Apple push service.
  /// A server that does not offer it (the option is off there) answers 404: [HydraApiException].
  Future<void> postLiveActivity(String activityToken, String robotId) async {
    final resp = await post('/api/push/live-activities', const Duration(seconds: 10), {'activityToken': activityToken, 'robotId': robotId});
    throwForStatus(resp);
  }

  /// Takes the token of a Live Activity back. The account removes only its own.
  Future<void> deleteLiveActivity(String activityToken) async {
    final resp = await call('DELETE', '$baseUrl/api/push/live-activities/${Uri.encodeComponent(activityToken)}',
        headers: {...clientHeaders, ...authHeaders}, timeout: const Duration(seconds: 10));
    throwForStatus(resp);
  }

  Future<void> deletePushDevice(String token) async {
    final resp = await call('DELETE', '$baseUrl/api/push/devices/$token',
        headers: {...clientHeaders, ...authHeaders}, timeout: const Duration(seconds: 10));
    throwForStatus(resp);
  }

  Future<RobotSafety?> getRobotSafety(dynamic robotId) async {
    try {
      return RobotSafety.fromJson(await getJson('/api/safety-limits?robotId=$robotId', const Duration(seconds: 5)));
    } on HydraApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<AssistantReply> postVoiceTurn(String transcript, String locale) async {
    final requestId = 'ios-${DateTime.now().millisecondsSinceEpoch}';
    return AssistantReply.fromJson(await postJson('/api/voice/turn', const Duration(seconds: 15), {
      'type': 'voice_turn',
      'requestId': requestId,
      'transcript': transcript,
      'locale': locale,
    }));
  }

  /// The project manifests the server finds next to itself, with a live probe for the services they declare
  /// (GET /api/ecosystem/status). A server that does not know the route answers 404: [HydraApiException].
  Future<EcosystemStatus> getEcosystemStatus() async =>
      EcosystemStatus.fromJson(await getJson('/api/ecosystem/status', const Duration(seconds: 10)));

  /// One timed read of GET /api/hydra-info on the current scheme, for the connection diagnostics: how long the answer
  /// took and what the server says about its version. Never throws; a miss is an [InfoProbe] without a time. It does not
  /// switch the scheme of the client.
  Future<InfoProbe> probeInfo({Duration timeout = const Duration(milliseconds: 1500)}) async {
    final watch = Stopwatch()..start();
    try {
      final resp = await get('/api/hydra-info', timeout);
      watch.stop();
      if (resp.statusCode != 200) return const InfoProbe();
      final json = jsonDecode(resp.body);
      if (json is! Map) return const InfoProbe();
      final api = json['remoteApiVersion'];
      final app = json['appVersion'];
      return InfoProbe(
        rttMs: watch.elapsedMilliseconds,
        remoteApiVersion: api is num ? api.toInt() : null,
        serverAppVersion: app is String && app.isNotEmpty ? app : null,
      );
    } catch (_) {
      return const InfoProbe();
    }
  }

  /// One small request to the server and how long it took, in milliseconds: the sample of the link health. It uses the
  /// route every server answers; nothing is read from the body. A failure (no answer, an error status or the time limit)
  /// is thrown.
  Future<int> pingRoundTripMs(Duration timeout) async {
    final probe = await probeInfo(timeout: timeout);
    final rtt = probe.rttMs;
    if (rtt == null) throw HydraApiException('No answer from $baseUrl in ${timeout.inMilliseconds} ms');
    return rtt;
  }

  /// The names of the work files (trajectories) a folder of the server lists in its index.json; the folder is checked by
  /// [WorkFiles.folderFor] before it gets here.
  Future<String> getWorkIndexBody(String folder) => getText('/$folder/index.json', const Duration(seconds: 10));

  /// One work file of a folder of the server.
  Future<String> getWorkFileBody(String folder, String file) => getText('/$folder/$file', const Duration(seconds: 10));

  /// Passes the presence heartbeat of the watch to the server; the server tells watch beats apart by
  /// the client header.
  Future<Map<String, dynamic>> postPresence(Map<String, dynamic> body) async {
    final resp = await call('POST', '$baseUrl${RobotCommandContract.presenceRelayPath}',
        headers: {'Content-Type': 'application/json', ...clientHeaders, ...controllerHeaders, ...authHeaders, 'X-Hydra-Client': 'watch'},
        body: jsonEncode({...body, 'controllerId': controllerIdValue}),
        timeout: const Duration(milliseconds: RobotCommandContract.presenceRelayTimeoutMs));
    return expectJson(resp);
  }

  /// Sends a voice confirmation to the server (the route and timeout are in [RobotCommandContract]).
  Future<Map<String, dynamic>> postVoiceConfirm(Map<String, dynamic> body) async {
    final resp = await call('POST', '$baseUrl${RobotCommandContract.voiceConfirmPath}',
        headers: {'Content-Type': 'application/json', ...clientHeaders, ...controllerHeaders, ...authHeaders, 'X-Hydra-Client': 'watch'},
        body: jsonEncode({...body, 'controllerId': controllerIdValue}),
        timeout: const Duration(milliseconds: RobotCommandContract.voiceConfirmTimeoutMs));
    return expectJson(resp);
  }
}
