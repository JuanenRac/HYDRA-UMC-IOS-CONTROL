// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_push_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The push notifications of the server against a real local dart:io HttpServer and a fake bridge to the system:
//   - turning them on asks for permission, takes the device token and registers it with the language of the app;
//   - a refused permission, a server that has them off and a failure each read as their own state;
//   - turning them off, and signing out, take the token off the server.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/push_bridge.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
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

class _Server {
  final HttpServer http;
  int commandStatus = 200;
  Map<String, dynamic> commandBody = {'success': true};
  Duration commandDelay = Duration.zero;
  final List<Map<String, dynamic>> commands = [];
  final List<String?> commandAuth = [];
  String validToken = 'token-1';
  int refreshCalls = 0;
  bool playing = false;
  int pushStatus = 200;
  final List<Map<String, dynamic>> pushRegistered = [];
  final List<String> pushRemoved = [];

  _Server(this.http) {
    http.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final WebSocket socket;
        try {
          socket = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (p) => p.contains('hydra.bearer') ? 'hydra.bearer' : null,
          );
        } catch (_) {
          // The client may drop mid-handshake (dart:io then throws inside the upgrade).
          return;
        }
        socket.listen((_) {});
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final json = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};
      request.response.headers.contentType = ContentType.json;
      final route = '${request.method} ${request.uri.path}';
      if (route == 'POST /api/login') {
        request.response.write(jsonEncode({'success': true, 'token': 'token-1', 'refreshToken': 'refresh-1'}));
      } else if (route == 'GET /api/settings') {
        request.response.write(jsonEncode({
          'activeControllerId': 'c1',
          'controllers': [
            {
              'id': 'c1',
              'robots': [
                {
                  'id': 1,
                  'online': true,
                  'joints': {'j1': 0, 'j2': 12.5},
                  'playbackState': {'isPlaying': playing},
                  'combinedWith': [],
                },
              ],
            },
          ],
        }));
      } else if (route == 'POST /api/refresh') {
        refreshCalls++;
        validToken = 'token-2';
        request.response.write(jsonEncode({'success': true, 'token': 'token-2', 'refreshToken': 'refresh-2'}));
      } else if (route == 'POST /api/logout') {
        request.response.write(jsonEncode({'success': true}));
      } else if (route == 'GET /api/system/metrics') {
        request.response.write(jsonEncode({'cpu_load': 3, 'memory_usage': 40, 'temp': 48.0, 'temp_is_real': false, 'uptime': 99}));
      } else if (route == 'POST /api/push/devices') {
        pushRegistered.add(json);
        request.response.statusCode = pushStatus;
        if (pushStatus == 200) request.response.write(jsonEncode({'registered': true}));
      } else if (request.method == 'DELETE' && request.uri.path.startsWith('/api/push/devices/')) {
        pushRemoved.add(request.uri.pathSegments.last);
        request.response.write(jsonEncode({'removed': true}));
      } else if (route == 'POST /api/robot/1/command') {
        commands.add(json);
        final auth = request.headers.value('authorization');
        commandAuth.add(auth);
        if (commandDelay > Duration.zero) await Future<void>.delayed(commandDelay);
        if (auth != 'Bearer $validToken') {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write(jsonEncode({'error': 'Access denied: token expired', 'code': 'TOKEN_EXPIRED'}));
        } else {
          request.response.statusCode = commandStatus;
          request.response.write(jsonEncode(commandBody));
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  }

  static Future<_Server> start() async => _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  int get port => http.port;
  Future<void> close() => http.close(force: true);
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeBridge implements PushBridge {
  bool grant = true;
  String? token = 'ab' * 32;
  int asked = 0;
  int unregistered = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return grant;
  }

  @override
  Future<String?> deviceToken({Duration timeout = const Duration(seconds: 10)}) async => token;

  @override
  Future<void> unregister() async => unregistered++;
}

Future<(_Server, RobotViewModel, _FakeBridge)> _signedIn({bool playing = false}) async {
  SharedPreferences.setMockInitialValues({});
  final server = await _Server.start();
  server.playing = playing;
  addTearDown(server.close);
  final bridge = _FakeBridge();
  final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pushBridge: bridge);
  addTearDown(vm.dispose);
  final ok = await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x'));
  expect(ok, isTrue);
  expect(vm.selectedRobot, isNotNull);
  return (server, vm, bridge);
}

void main() {
  test('turning them on registers the token with the language of the app', () async {
    final (server, vm, bridge) = await _signedIn();
    await vm.setPushNotifications(true);

    expect(bridge.asked, greaterThan(0));
    expect(vm.pushState, PushState.registered);
    final sent = server.pushRegistered.last;
    expect(sent['token'], 'ab' * 32);
    expect(sent['platform'], 'ios');
    expect(sent['locale'], isA<String>());
    expect((sent['locale'] as String).length, 2);
  });

  test('a refused permission, a server with push off and a failure each read as their own state', () async {
    final (server, vm, bridge) = await _signedIn();
    bridge.grant = false;
    await vm.setPushNotifications(true);
    expect(vm.pushState, PushState.denied);
    expect(server.pushRegistered, isEmpty);

    bridge.grant = true;
    server.pushStatus = 404;
    await vm.syncPushRegistration();
    expect(vm.pushState, PushState.serverOff);
    expect(vm.isLoggedIn, isTrue, reason: 'a 404 must not end the session');

    server.pushStatus = 500;
    await vm.syncPushRegistration();
    expect(vm.pushState, PushState.failed);

    server.pushStatus = 200;
    bridge.token = null;
    await vm.syncPushRegistration();
    expect(vm.pushState, PushState.failed, reason: 'the system never gave a token');
  });

  test('turning them off takes the token off the server and the system', () async {
    final (server, vm, bridge) = await _signedIn();
    await vm.setPushNotifications(true);
    await vm.setPushNotifications(false);
    expect(server.pushRemoved, ['ab' * 32]);
    expect(bridge.unregistered, 1);
    expect(vm.pushState, PushState.off);
  });

  test('signing out takes the token off the server', () async {
    final (server, vm, _) = await _signedIn();
    await vm.setPushNotifications(true);
    vm.logout();
    await _until(() => server.pushRemoved.isNotEmpty);
    expect(server.pushRemoved, ['ab' * 32]);
  });

  test('nothing is asked while the person has not turned them on', () async {
    final (server, vm, bridge) = await _signedIn();
    await vm.syncPushRegistration();
    expect(bridge.asked, 0);
    expect(server.pushRegistered, isEmpty);
    expect(vm.pushNotifications, isFalse);
  });
}
