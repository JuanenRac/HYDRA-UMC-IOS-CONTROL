// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/discovery.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Finds servers on the local network, by two independent paths that feed the same
// "Scan local network" sheet of ui/login_screen.dart:
//   - discoverMdns(): mDNS/Bonjour query for the "_hydra._tcp.local" service the
//     server publishes. Near-instant when the network delivers multicast replies.
//     iOS drops multicast *receive* for an app without Apple's Multicast Networking
//     entitlement (com.apple.developer.networking.multicast, granted per app and
//     listed in Runner.entitlements): without it the query goes out but no reply
//     may come, and the function finishes with nothing found.
//   - scanSubnets(): GET /api/hydra-info against every host of the /24 networks of
//     the device. Slower, but needs no multicast, so it is the path that always works.
//
// scanSubnets() takes its prefixes from the network interfaces of the device
// (dart:io NetworkInterface.list(): no permission and no plugin) and falls back to
// 192.168.1.x only when the enumeration returns nothing, as on a locked-down simulator.
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../models/server_info.dart';
import 'hydra_api_client.dart';
import 'tls_settings.dart';

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
          final apiClient = HydraApiClient(host, port, client: createDiscoveryClient());
          try {
            final info = await apiClient.getHydraInfo();
            if (info != null) yield ServerInfo.fromHydraInfo(host, port, info, useTls: apiClient.usesTls);
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
/// True for the interface names iOS (and the other platforms) give to the
/// mobile-data link (`pdp_ip*`, `rmnet*`, `ccmni*`, `wwan*`) and to VPN or
/// tunnel interfaces (`utun*`, `ipsec*`, `ppp*`, `tun*`, `tap*`, `wg*`).
bool isMobileOrVpnInterface(String name) {
  final n = name.toLowerCase();
  const prefixes = ['pdp_ip', 'rmnet', 'ccmni', 'wwan', 'utun', 'ipsec', 'ppp', 'tun', 'tap', 'wg'];
  return prefixes.any(n.startsWith);
}

/// The /24 prefix ("a.b.c") of every IPv4 address in [interfaces]
/// (name -> addresses), leaving out the mobile-data and VPN ones when
/// [skipMobileAndVpn] is true.
Set<String> prefixesOfInterfaces(Map<String, List<String>> interfaces, {bool skipMobileAndVpn = false}) {
  final prefixes = <String>{};
  for (final entry in interfaces.entries) {
    if (skipMobileAndVpn && isMobileOrVpnInterface(entry.key)) continue;
    for (final address in entry.value) {
      final parts = address.split('.');
      if (parts.length == 4) prefixes.add(parts.sublist(0, 3).join('.'));
    }
  }
  return prefixes;
}

Future<List<String>> _candidatePrefixes({String? lastHost, bool skipMobileAndVpn = false}) async {
  final prefixes = <String>{};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    prefixes.addAll(prefixesOfInterfaces(
      {for (final iface in interfaces) iface.name: iface.addresses.map((a) => a.address).toList()},
      skipMobileAndVpn: skipMobileAndVpn,
    ));
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
///
/// With [skipMobileAndVpn] the mobile-data and VPN interfaces of the phone are
/// left out of the sweep (off by default, which scans every interface).
Stream<ServerInfo> scanSubnets({String? lastHost, bool skipMobileAndVpn = false}) async* {
  final prefixes = await _candidatePrefixes(lastHost: lastHost, skipMobileAndVpn: skipMobileAndVpn);

  final client = createDiscoveryClient();
  try {
    for (final prefix in prefixes) {
      final hosts = List.generate(254, (i) => '$prefix.${i + 1}');
      var index = 0;
      final controller = StreamController<ServerInfo>();
      Future<void> worker() async {
        while (index < hosts.length) {
          final host = hosts[index++];
          try {
            final apiClient = HydraApiClient(host, defaultPort, client: client);
            final info = await apiClient.getHydraInfo();
            if (info != null && !controller.isClosed) {
              controller.add(ServerInfo.fromHydraInfo(host, defaultPort, info, useTls: apiClient.usesTls));
            }
          } catch (_) {
            // One host that answers with something unexpected must not abort
            // the sweep (or leave the "searching" spinner running forever).
          }
        }
      }

      final workers = List.generate(_scanConcurrency, (_) => worker());
      unawaited(Future.wait(workers).whenComplete(controller.close));
      yield* controller.stream;
    }
  } finally {
    client.close();
  }
}
