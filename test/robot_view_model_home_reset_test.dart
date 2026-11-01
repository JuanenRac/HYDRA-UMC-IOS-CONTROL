// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_home_reset_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// HOME/RESET through the view model against a real local dart:io HttpServer (no
// robot, no mocked client): nothing goes out while the switch is off or a rule
// blocks it, the command carries its number, and the refusals of the server read
// in their own words with the pose put back.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/util/home_reset.dart';

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
  bool playing = false;
  final List<Map<String, dynamic>> commands = [];

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
                  'pos': {'x': 10, 'y': 20, 'z': 30, 'a': 1, 'b': 2, 'c': 3},
                  'playbackState': {'isPlaying': playing},
                  'combinedWith': [],
                },
              ],
            },
          ],
        }));
      } else if (route == 'GET /api/system/metrics') {
        request.response.write(jsonEncode({'cpu_load': 3, 'memory_usage': 40, 'temp': 48.0, 'temp_is_real': false, 'uptime': 99}));
      } else if (route == 'POST /api/robot/1/command') {
        commands.add(json);
        request.response.statusCode = commandStatus;
        request.response.write(jsonEncode(commandBody));
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
  test('nothing goes out while the switch is off', () async {
    final (server, vm) = await _signedIn();
    expect(vm.homeResetEnabled, isFalse);
    expect(vm.homeResetBlock(), HomeResetBlock.off);

    vm.homeReset();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(server.commands, isEmpty);
    expect(vm.lastError!.kind, HydraErrorKind.homeResetBlocked);
    expect(vm.selectedRobot!.posAxis('x'), 10);
  });

  test('with the switch on the reset goes out numbered, shows zero at once and sends nothing else', () async {
    final (server, vm) = await _signedIn();
    await vm.setHomeResetEnabled(true);
    expect(vm.homeResetBlock(), HomeResetBlock.none);

    vm.homeReset();
    expect(vm.selectedRobot!.posAxis('x'), 0);
    await _until(() => server.commands.isNotEmpty);

    expect(server.commands.single['command'], 'reset');
    expect(server.commands.single['params'], {'target': 'robot'});
    expect(server.commands.single['seq'], isA<int>());
    expect(server.commands.single['seq'] as int, greaterThan(0));
  });

  test('a robot that is playing is not reset', () async {
    final (server, vm) = await _signedIn(playing: true);
    await vm.setHomeResetEnabled(true);
    expect(vm.homeResetBlock(), HomeResetBlock.moving);

    vm.homeReset();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(server.commands, isEmpty);
  });

  test('an unconfirmed STOP holds the reset back', () async {
    final (server, vm) = await _signedIn();
    await vm.setHomeResetEnabled(true);
    vm.stopAllUnconfirmed = true;
    expect(vm.homeResetBlock(), HomeResetBlock.stopPending);

    vm.homeReset();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(server.commands, isEmpty);
  });

  test('an older server that does not know reset is remembered and the pose is put back', () async {
    final (server, vm) = await _signedIn();
    await vm.setHomeResetEnabled(true);
    server.commandStatus = 400;
    server.commandBody = {'error': 'unknown command'};

    vm.homeReset();
    await _until(() => vm.lastError != null);

    expect(vm.lastError!.kind, HydraErrorKind.homeResetBlocked);
    expect(vm.lastError!.params['block'], 'notSupported');
    expect(vm.homeResetServerSupports, isFalse);
    expect(vm.homeResetBlock(), HomeResetBlock.notSupported);
    expect(vm.selectedRobot!.posAxis('x'), 10);

    vm.homeReset();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.commands.length, 1, reason: 'a second press sends nothing more');
  });

  test('a 403 reads as a role problem and the pose is put back', () async {
    final (server, vm) = await _signedIn();
    await vm.setHomeResetEnabled(true);
    server.commandStatus = 403;
    server.commandBody = {'error': 'forbidden'};

    vm.homeReset();
    await _until(() => vm.lastError != null);

    expect(vm.lastError!.params['block'], 'role');
    expect(vm.selectedRobot!.posAxis('x'), 10);
    expect(vm.homeResetServerSupports, isTrue);
  });
}
