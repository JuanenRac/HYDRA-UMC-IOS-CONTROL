// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_background_pause_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Real gap this closes: this app relied entirely on iOS's own OS-level
// socket timeout to eventually notice a backgrounded connection was dead,
// rather than actively closing it the moment AppLifecycleState.paused
// fires (main.dart's own _RootGateState.didChangeAppLifecycleState).
// Drives RobotViewModel.pauseForBackground() against a real local
// dart:io HttpServer/WebSocket - same real-socket approach
// hydra_websocket_reconnect_test.dart and
// robot_view_model_silent_refresh_test.dart already use, no mocked
// HydraApiClient/HydraWebSocket anywhere in this file.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
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

/// Real local HTTP + WebSocket server, minimal enough for login() +
/// pauseForBackground() - answers login/settings, accepts the /ws
/// upgrade, and records whether the server side ever observed the
/// connection actually close.
class _FakeServer {
  final HttpServer server;
  bool wsClosedByClient = false;
  WebSocket? _activeSocket;

  _FakeServer(this.server) {
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _activeSocket = socket;
        socket.listen(
          (_) {},
          onDone: () => wsClosedByClient = true,
        );
        return;
      }
      request.response.headers.contentType = ContentType.json;
      switch ('${request.method} ${request.uri.path}') {
        case 'POST /api/login':
          request.response.write(jsonEncode({'success': true, 'token': 'tok', 'refreshToken': 'reftok'}));
          break;
        case 'GET /api/settings':
          request.response.write(jsonEncode({'controllers': []}));
          break;
        default:
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

  Future<void> close() async {
    await _activeSocket?.close();
    await server.close(force: true);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pauseForBackground() actually closes the real WebSocket and reports disconnected', () async {
    final fakeServer = await _FakeServer.start();
    addTearDown(fakeServer.close);

    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    final server = ServerInfo(host: '127.0.0.1', port: fakeServer.port, username: 'alice', password: 'irrelevant-for-this-test');

    final ok = await vm.login(server);
    expect(ok, isTrue);

    final connectDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (vm.connectionStatus != 'connected' && DateTime.now().isBefore(connectDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(vm.connectionStatus, 'connected', reason: 'setup: a real WS connection must actually establish first');

    vm.pauseForBackground();

    // The real, observable effect this fix exists for: the server side
    // must see the connection actually go away - not just the client's
    // own connectionStatus flag flipping without the socket really closing.
    final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (!fakeServer.wsClosedByClient && DateTime.now().isBefore(closeDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(fakeServer.wsClosedByClient, isTrue, reason: 'the real socket must actually close server-side, not just flip a local flag');
    expect(vm.connectionStatus, 'disconnected');
  });

  test('pauseForBackground() is a real no-op while already disconnected (never logged in)', () async {
    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);

    expect(vm.connectionStatus, 'disconnected');
    // Must not throw against a null _ws/_metricsTimer.
    vm.pauseForBackground();
    expect(vm.connectionStatus, 'disconnected');
  });

  test('reconnectIfNeeded() after pauseForBackground() re-establishes a real connection', () async {
    final fakeServer = await _FakeServer.start();
    addTearDown(fakeServer.close);

    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(vm.dispose);
    final server = ServerInfo(host: '127.0.0.1', port: fakeServer.port, username: 'alice', password: 'irrelevant-for-this-test');

    final ok = await vm.login(server);
    expect(ok, isTrue);
    final connectDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (vm.connectionStatus != 'connected' && DateTime.now().isBefore(connectDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    vm.pauseForBackground();
    expect(vm.connectionStatus, 'disconnected');

    // The real resume path (main.dart's own AppLifecycleState.resumed
    // handler) must actually bring the connection back.
    vm.reconnectIfNeeded();
    final reconnectDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (vm.connectionStatus != 'connected' && DateTime.now().isBefore(reconnectDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(vm.connectionStatus, 'connected', reason: 'resume must actually re-establish a real WebSocket connection');
  });
}
