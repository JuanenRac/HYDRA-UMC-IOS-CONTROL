// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/discovery.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Concurrent local-subnet scan hitting GET /api/hydra-info on every
// candidate host - same approach HYDRA-UMC-SUITE's own
// hydra_suite/net/discovery.py and HYDRA-UMC-ANDROID-CONTROL's own
// network/Discovery.kt both use (mDNS/Bonjour would be nicer - server.ts
// does publish a real _hydra._tcp service now - but a manual subnet scan
// needs no extra native platform plugin and always works as a fallback,
// so it stays the primary path here too until Bonjour support is added
// to all 3 clients together rather than piecemeal).
//
// The prefix list to scan comes from this device's own network
// interfaces (dart:io's NetworkInterface.list(), portable and
// permission-free on iOS/Android/Windows/macOS/Linux - no extra platform
// plugin needed) rather than a single hardcoded guess: a phone's LAN is
// just as likely to be 192.168.0.x, 192.168.68.x (common ISP router
// defaults) or 10.x.x.x as it is to be 192.168.1.x, and scanning only the
// latter silently finds nothing on every other network. 192.168.1.x is
// kept only as a last-resort fallback for the rare case interface
// enumeration itself returns nothing (e.g. a locked-down simulator).
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server_info.dart';
import 'hydra_api_client.dart';

const int defaultPort = 3000;
const int _scanConcurrency = 32;

/// Every distinct /24 prefix ("a.b.c") worth scanning: this device's own
/// non-loopback IPv4 interfaces first, then [lastHost]'s subnet if it
/// differs, then the common-default fallback so a fresh install with no
/// saved host and an interface query that comes back empty still tries
/// something instead of scanning nothing.
Future<List<String>> _candidatePrefixes({String? lastHost}) async {
  final prefixes = <String>{};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4) prefixes.add(parts.sublist(0, 3).join('.'));
      }
    }
  } on SocketException {
    // No usable interface info (sandboxed platform, no network) - fall
    // through to the lastHost/default fallbacks below.
  }

  if (lastHost != null) {
    final parts = lastHost.split('.');
    if (parts.length == 4) prefixes.add(parts.sublist(0, 3).join('.'));
  }

  if (prefixes.isEmpty) prefixes.add('192.168.1');
  return prefixes.toList();
}

/// Scans every candidate /24 (this device's own real subnet(s), plus
/// [lastHost]'s subnet and a common-default fallback - see
/// [_candidatePrefixes]) for a real HYDRA-UMC STUDIO server, yielding each
/// match as soon as it's found rather than waiting for the whole sweep to
/// finish.
Stream<ServerInfo> scanSubnets({String? lastHost}) async* {
  final prefixes = await _candidatePrefixes(lastHost: lastHost);

  final client = http.Client();
  try {
    for (final prefix in prefixes) {
      final hosts = List.generate(254, (i) => '$prefix.${i + 1}');
      var index = 0;
      final controller = StreamController<ServerInfo>();
      Future<void> worker() async {
        while (index < hosts.length) {
          final host = hosts[index++];
          final apiClient = HydraApiClient(host, defaultPort, client: client);
          final info = await apiClient.getHydraInfo();
          if (info != null && !controller.isClosed) {
            controller.add(ServerInfo.fromHydraInfo(host, defaultPort, info));
          }
        }
      }

      final workers = List.generate(_scanConcurrency, (_) => worker());
      unawaited(Future.wait(workers).then((_) => controller.close()));
      yield* controller.stream;
    }
  } finally {
    client.close();
  }
}
