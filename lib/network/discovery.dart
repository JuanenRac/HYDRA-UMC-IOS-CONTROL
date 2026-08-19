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
// Deliberately does NOT try to enumerate the phone's own real subnet
// (no portable, permission-free way to read the local IP from Dart alone
// without an extra platform plugin) - scans the single most common
// private LAN prefix (192.168.1.x) plus whatever the last-used host
// implies, and always allows manual entry. Real subnet auto-detection is
// a documented gap, not a silent omission - see mejoras_futuras.txt.
// =============================================================================

import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/server_info.dart';
import 'hydra_api_client.dart';

const int defaultPort = 3000;
const int _scanConcurrency = 32;

/// Scans 192.168.1.1-254 (and, if [lastHost] is on a different /24, that
/// subnet too) for a real HYDRA-UMC STUDIO server, yielding each match as
/// soon as it's found rather than waiting for the whole sweep to finish.
Stream<ServerInfo> scanSubnets({String? lastHost}) async* {
  final prefixes = <String>{'192.168.1'};
  if (lastHost != null) {
    final parts = lastHost.split('.');
    if (parts.length == 4) prefixes.add(parts.sublist(0, 3).join('.'));
  }

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
