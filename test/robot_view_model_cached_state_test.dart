// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_cached_state_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// real end-to-end coverage that RobotViewModel.init surfaces
// network/state_cache.dart's own persisted last-known tree as a real,
// visible "this might be stale" fact (isShowingCachedState/
// cachedStateSavedAt) instead of silently rendering it as if it were
// live data - and that the flag is really cleared the moment a live
// server response replaces it, not merely asserted against the private
// fields in isolation. Mirrors robot_view_model_silent_refresh_test.dart's
// own real-local-server approach - no mocked HydraApiClient anywhere here.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/state_cache.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';

class _FakeSecureBackend implements SecureTokenBackend {
  final Map<String, String> store = {};
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> delete(String key) async => store.remove(key);
}

/// Minimal real local server - just enough for connect()'s own real REST
/// call and WS upgrade to succeed. No login/refresh endpoints: this file
/// seeds a session directly via AuthPrefs instead of going through
/// RobotViewModel.login(), so init() restores it on its own.
class _FakeServer {
  final HttpServer server;
  _FakeServer(this.server) {
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await WebSocketTransformer.upgrade(request);
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/api/settings') {
        request.response.write(jsonEncode({'controllers': []}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  }

  static Future<_FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeServer(server);
  }

  int get port => server.port;
  Future<void> close() async => server.close(force: true);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('init() surfaces a loaded cache as isShowingCachedState with its real saved instant', () async {
    await StateCache().saveState({
      'controllers': [
        {
          'id': 'c1',
          'robots': [
            {'id': 1, 'name': 'ARM-1', 'online': true},
          ],
        },
      ],
    });

    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    // No saved connection in AuthPrefs -> init() never auto-reconnects, so
    // the loaded cache stays the only data on screen, exactly the real
    // "just came back into range with a dead/unreachable server" case.
    await vm.init();

    expect(vm.isShowingCachedState, isTrue);
    expect(vm.cachedStateSavedAt, isNotNull);
    expect(vm.state.raw['controllers'], isNotEmpty);
  });

  test('a real, successful connect() clears isShowingCachedState even though init() loaded a stale cache first', () async {
    await StateCache().saveState({'controllers': []});

    final fakeServer = await _FakeServer.start();
    addTearDown(fakeServer.close);

    final authPrefs = AuthPrefs(secureBackend: _FakeSecureBackend());
    await authPrefs.saveConnection('127.0.0.1', fakeServer.port);
    await authPrefs.saveToken('real-token', 'alice');

    final vm = RobotViewModel(authPrefs: authPrefs);
    addTearDown(vm.dispose);
    await vm.init();

    expect(
      vm.isShowingCachedState,
      isFalse,
      reason: 'a real live GET /api/settings response must clear the cached-data flag',
    );

    // init()'s own await only covers the REST call - it starts the real WS
    // connect in the background without waiting for it. Settle that real
    // connection before this test returns and tears vm down, so a late
    // onStatus callback never fires against an already-disposed
    // RobotViewModel (the same real observable-side-effect polling
    // robot_view_model_silent_refresh_test.dart's own sibling test uses).
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (vm.connectionStatus != 'connected' && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(vm.connectionStatus, 'connected');
  });

  test('an app launched with no cache at all never claims to be showing cached data', () async {
    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    await vm.init();

    expect(vm.isShowingCachedState, isFalse);
    expect(vm.cachedStateSavedAt, isNull);
  });
}
