// =============================================================================
// HYDRA-UMC-IOS-CONTROL - WebSocket endpoint encoding test
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/network/hydra_websocket.dart';

void main() {
  test('encodes an opaque bearer token as one WebSocket query value', () {
    final uri = HydraWebSocket.buildConnectionUri(
      host: '192.168.1.20',
      port: 3000,
      token: 'token+with/characters?and=value',
    );

    expect(uri.scheme, 'ws');
    expect(uri.path, '/ws');
    expect(uri.queryParameters['token'], 'token+with/characters?and=value');
    expect(uri.queryParameters['remoteApiVersion'], '2');
  });
}
