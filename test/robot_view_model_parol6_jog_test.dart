// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_parol6_jog_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The jog of a Parol6 against a real local dart:io HttpServer (no mocked client):
//   - a jog is resolved once against the real kinematics and every axis command carries the same joints;
//   - a target out of reach sends nothing and says so;
//   - the base rotation (J1) alone is a joints override that stops at the real limit.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
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
                  'model': 'Parol6 (6-DOF)',
                  'pos': {'x': 200.0, 'y': 0.0, 'z': 0.0, 'a': 0.0, 'b': 0.0, 'c': 0.0},
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

Future<(_Server, RobotViewModel)> _signedIn({bool playing = false}) async {
  SharedPreferences.setMockInitialValues({});
  final server = await _Server.start();
  server.playing = playing;
  addTearDown(server.close);
  final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
  addTearDown(vm.dispose);
  final ok = await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x'));
  expect(ok, isTrue);
  expect(vm.selectedRobot, isNotNull);
  return (server, vm);
}

void main() {
  test('a Parol6 jog goes out as one resolved pose: the same joints on every axis command', () async {
    final (server, vm) = await _signedIn();

    vm.jogXYZ('robot', 1, 0, 1, 10.0);
    await _until(() => server.commands.length >= 2);

    expect(server.commands.map((c) => c['params']['axis']), ['x', 'z']);
    final first = server.commands[0]['params'] as Map<String, dynamic>;
    final second = server.commands[1]['params'] as Map<String, dynamic>;
    expect(first['target'], 'robot');
    expect(first['amount'], 10.0);
    expect(first['joints'], isA<Map>());
    expect((first['joints'] as Map).keys, ['j1', 'j2', 'j3', 'j4', 'j5', 'j6']);
    expect(second['joints'], first['joints'], reason: 'one pose for the whole tick');
    expect(vm.selectedRobot!.posAxis('x'), 210.0);
    expect(vm.selectedRobot!.posAxis('z'), 10.0);
  });

  test('a jog out of reach sends nothing and says so', () async {
    final (server, vm) = await _signedIn();

    vm.jogXYZ('robot', 1, 0, 0, 5000.0);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(server.commands, isEmpty);
    expect(vm.lastError!.kind, HydraErrorKind.jogOutOfReach);
    expect(vm.selectedRobot!.posAxis('x'), 200.0);
  });

  test('the base rotation is a joints override and stops at the real limit', () async {
    final (server, vm) = await _signedIn();

    vm.jogJ1(1, 10.0);
    await _until(() => server.commands.isNotEmpty);

    final params = server.commands.single['params'] as Map<String, dynamic>;
    expect(params['axis'], 'x');
    expect(params['amount'], 0.0);
    expect((params['joints'] as Map)['j1'], 10.0);
    expect(vm.selectedRobot!.joint('j1'), 10.0);

    // Far enough to be clamped to the limit of the arm, then nothing more is sent at the limit.
    await _until(() => vm.jogBlocked() == false);
    vm.jogJ1(1, 500.0);
    await _until(() => server.commands.length >= 2);
    expect(((server.commands[1]['params'] as Map)['joints'] as Map)['j1'], 97.4);
    await _until(() => vm.jogBlocked() == false);
    vm.jogJ1(1, 10.0);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.commands, hasLength(2));
  });
}
