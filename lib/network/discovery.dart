// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/discovery.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Two independent discovery paths, both feeding the same "Scan local
// network" sheet in ui/login_screen.dart:
//   - discoverMdns(): real mDNS/Bonjour, querying the "_hydra._tcp.local"
//     service server.ts publishes - near-instant on a network that
//     delivers the multicast replies.
//   - scanSubnets(): brute-force GET /api/hydra-info against every host on
//     the device's own local /24(s) - slower, but needs no multicast
//     delivery at all, so it stays the guaranteed fallback. In particular,
//     iOS silently drops multicast *receive* for any app that wasn't
//     granted Apple's dedicated Multicast Networking entitlement
//     (com.apple.developer.networking.multicast - requested from Apple
//     per-app, not something a plain `flutter build ios` gets for free):
//     an unentitled iOS build can still send the mDNS query but may never
//     see a reply, so discoverMdns() failing quietly on iOS is expected
//     until that entitlement is requested and added to Runner.entitlements,
//     not a bug in this file. HYDRA-UMC-SUITE and HYDRA-UMC-ANDROID-CONTROL
//     still only scan subnets - this app is the first of the 3 clients to
//     add real mDNS, additively, without dropping the fallback either of
//     them still relies on.
//
// The prefix list scanSubnets() scans comes from this device's own network
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
import 'package:multicast_dns/multicast_dns.dart';

import '../models/server_info.dart';
import 'hydra_api_client.dart';

const String _mdnsServiceType = '_hydra._tcp.local';

/// Queries mDNS/Bonjour for real HYDRA-UMC servers (HYDRA-UMC-SERVER's own
/// "_hydra._tcp" publish) and resolves every instance found down to a real
/// [ServerInfo] via the same GET /api/hydra-info [scanSubnets] uses, so a
/// match found this way is verified exactly the same way, not just assumed
/// live because mDNS answered. Any failure along the way (no multicast
/// socket permission, MDnsClient.start() throwing on a locked-down
/// platform, a timeout with zero replies) yields nothing rather than
/// throwing - see this file's own header comment on why that's expected
/// on an unentitled iOS build, and [scanSubnets] keeps working
/// independently either way since login_screen.dart runs both at once.
Stream<ServerInfo> discoverMdns({Duration timeout = const Duration(seconds: 4)}) async* {
  final client = MDnsClient();
  final seen = <String>{};
  try {
    await client.start();
    final ptrQuery = client
        .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_mdnsServiceType))
        .timeout(timeout, onTimeout: (sink) => sink.close());
    await for (final ptr in ptrQuery) {
      final srvQuery = client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(timeout, onTimeout: (sink) => sink.close());
      await for (final srv in srvQuery) {
        final ipQuery = client
            .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
            .timeout(timeout, onTimeout: (sink) => sink.close());
        await for (final ip in ipQuery) {
          final host = ip.address.address;
          final port = srv.port;
          if (!seen.add('$host:$port')) continue;
          final apiClient = HydraApiClient(host, port);
          try {
            final info = await apiClient.getHydraInfo();
            if (info != null) yield ServerInfo.fromHydraInfo(host, port, info);
          } finally {
            apiClient.close();
          }
        }
      }
    }
  } catch (_) {
    // Best-effort discovery path - see header comment.
  } finally {
    client.stop();
  }
}

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
