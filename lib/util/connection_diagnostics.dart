// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/connection_diagnostics.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The facts the connection diagnostics screen shows, and the plain-text report the person can copy to send to whoever
// helps. The report never carries a password, a token, a cookie or a certificate: only the scheme, the address the
// person typed, the SHA-256 fingerprint they chose to trust (public), versions, round-trip times and the state of the
// link. Its labels are English on purpose, like the telemetry log: a trail to read, not chrome of the app.
// =============================================================================

import 'link_health.dart';

/// How the app decides whether to trust the certificate of the server.
enum TrustMode { plainHttp, pinnedFingerprint, customAuthority, systemCertificates }

/// One answer of GET /api/hydra-info: how long it took and what the server said about itself.
class InfoProbe {
  final int? rttMs;
  final int? remoteApiVersion;
  final String? serverAppVersion;
  const InfoProbe({this.rttMs, this.remoteApiVersion, this.serverAppVersion});

  bool get answered => rttMs != null;
}

class ConnectionDiagnostics {
  final String scheme;
  final String host;
  final int port;
  final TrustMode trust;
  final String pinnedFingerprint;
  final int? remoteApiVersion;
  final String? serverAppVersion;
  final String clientVersion;

  /// The round-trip times (ms) of the probes of this run, null for one that got no answer.
  final List<int?> latenciesMs;
  final LinkLevel level;
  final String websocket;
  final String? role;
  final bool showingSavedData;

  const ConnectionDiagnostics({
    required this.scheme,
    required this.host,
    required this.port,
    required this.trust,
    this.pinnedFingerprint = '',
    this.remoteApiVersion,
    this.serverAppVersion,
    required this.clientVersion,
    this.latenciesMs = const [],
    this.level = LinkLevel.unknown,
    this.websocket = 'disconnected',
    this.role,
    this.showingSavedData = false,
  });

  List<int> get answeredMs => [for (final v in latenciesMs) ?v];

  int? get minMs => answeredMs.isEmpty ? null : answeredMs.reduce((a, b) => a < b ? a : b);
  int? get maxMs => answeredMs.isEmpty ? null : answeredMs.reduce((a, b) => a > b ? a : b);
  int? get averageMs => answeredMs.isEmpty ? null : (answeredMs.reduce((a, b) => a + b) / answeredMs.length).round();
  int get lost => latenciesMs.length - answeredMs.length;

  /// Which trust applies to a connection with these settings.
  static TrustMode trustFor({required String scheme, required String pinnedFingerprint, required String customCaPem}) {
    if (scheme != 'https') return TrustMode.plainHttp;
    if (pinnedFingerprint.trim().isNotEmpty) return TrustMode.pinnedFingerprint;
    if (customCaPem.trim().isNotEmpty) return TrustMode.customAuthority;
    return TrustMode.systemCertificates;
  }

  /// The plain-text report, at most [maxLines] lines.
  String report({int maxLines = 100}) {
    String show(Object? v) => v == null ? 'unknown' : '$v';
    String ms(int? v) => v == null ? 'none' : '$v ms';
    final lines = <String>[
      'HYDRA-UMC Control (iOS) connection report',
      'client version: $clientVersion',
      'address: $scheme://$host:$port',
      'trust: ${trust.name}',
      if (pinnedFingerprint.isNotEmpty) 'pinned fingerprint (SHA-256): $pinnedFingerprint',
      'server remote API version: ${show(remoteApiVersion)}',
      'server app version: ${show(serverAppVersion)}',
      'probes: ${latenciesMs.length} sent, $lost without answer',
      'latency: min ${ms(minMs)}, average ${ms(averageMs)}, max ${ms(maxMs)}',
      for (var i = 0; i < latenciesMs.length; i++) '  probe ${i + 1}: ${ms(latenciesMs[i])}',
      'link level: ${level.name}',
      'websocket: $websocket',
      'session role: ${show(role)}',
      'showing saved data: ${showingSavedData ? 'yes' : 'no'}',
    ];
    return lines.take(maxLines).join('\n');
  }
}
