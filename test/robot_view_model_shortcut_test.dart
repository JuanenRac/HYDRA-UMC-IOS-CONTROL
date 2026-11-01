// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_shortcut_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The global stop asked for by a system shortcut against a real local dart:io HttpServer and a fake bridge:
//   - a waiting request goes out as the very same POST /api/stop-all the STOP button makes, with the session of the person;
//   - a request made before the person is signed in waits for the session and then goes out;
//   - with no request nothing is sent.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/shortcut_bridge.dart';
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
  final List<String?> stopAllAuth = [];

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
      } else if (route == 'POST /api/stop-all') {
        stopAllAuth.add(request.headers.value('authorization'));
        request.response.write(jsonEncode({'success': true, 'robots': [{'robotId': 1, 'stopped': true, 'valvesOff': 0, 'pumpsOff': 0}]}));
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

class _FakeShortcuts implements ShortcutBridge {
  bool waiting = false;
  void Function()? callback;
  @override
  Future<bool> takeGlobalStop() async {
    final was = waiting;
    waiting = false;
    return was;
  }

  @override
  void onGlobalStopRequested(void Function() cb) => callback = cb;
}

Future<(_Server, RobotViewModel, _FakeShortcuts)> _signedIn({bool playing = false, bool login = true}) async {
  SharedPreferences.setMockInitialValues({});
  final server = await _Server.start();
  server.playing = playing;
  addTearDown(server.close);
  final fake = _FakeShortcuts();
  final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), shortcutBridge: fake);
  addTearDown(vm.dispose);
  if (login) {
    final ok = await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x'));
    expect(ok, isTrue);
    expect(vm.selectedRobot, isNotNull);
  }
  return (server, vm, fake);
}

void main() {
  test('a waiting request goes out as the global stop of the STOP button, with the session of the person', () async {
    final (server, vm, shortcuts) = await _signedIn();
    shortcuts.waiting = true;
    await vm.serveShortcutStop();
    expect(server.stopAllAuth, ['Bearer token-1']);
    expect(vm.stopAllResult, isNotNull);
    expect(shortcuts.waiting, isFalse, reason: 'a request is served once');
  });

  test('a request that arrives while the app is open is served at once', () async {
    final (server, _, shortcuts) = await _signedIn();
    expect(shortcuts.callback, isNotNull);
    shortcuts.waiting = true;
    shortcuts.callback!();
    await _until(() => server.stopAllAuth.isNotEmpty);
    expect(server.stopAllAuth, hasLength(1));
  });

  test('with no request nothing is sent', () async {
    final (server, vm, _) = await _signedIn();
    await vm.serveShortcutStop();
    expect(server.stopAllAuth, isEmpty);
  });

  test('a request made before the person is signed in waits for the session and then goes out', () async {
    final (server, vm, shortcuts) = await _signedIn(login: false);
    shortcuts.waiting = true;
    await vm.serveShortcutStop();
    expect(server.stopAllAuth, isEmpty);
    final ok = await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x'));
    expect(ok, isTrue);
    await _until(() => server.stopAllAuth.isNotEmpty);
    expect(server.stopAllAuth, ['Bearer token-1']);
  });
}
