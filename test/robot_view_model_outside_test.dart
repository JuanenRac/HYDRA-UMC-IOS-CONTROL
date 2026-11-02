// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_outside_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The view model against a real local dart:io HttpServer and fake bridges to the system:
//   - the ecosystem tab reads GET /api/ecosystem/status, tells an old server from a good one and is not read twice in a row;
//   - the connection diagnostics probe GET /api/hydra-info, grade the link and name the scheme;
//   - the dictation asks for the recognition on the device alone unless the person allowed more, and only fills a text;
//   - every switch of what reaches out of the app is saved and starts off.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/native_bridges.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/util/connection_diagnostics.dart';
import 'package:hydra_umc_control/util/link_health.dart';

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
  int ecosystemStatus = 200;
  int ecosystemReads = 0;
  int infoReads = 0;
  bool infoWorks = true;

  _Server(this.http) {
    http.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          final socket = await WebSocketTransformer.upgrade(request, protocolSelector: (p) => p.contains('hydra.bearer') ? 'hydra.bearer' : null);
          socket.listen((_) {});
        } catch (_) {}
        return;
      }
      await utf8.decoder.bind(request).join();
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
                {'id': 1, 'online': true, 'joints': {'j1': 0}, 'playbackState': {'isPlaying': false}, 'combinedWith': []},
              ],
            },
          ],
        }));
      } else if (route == 'GET /api/system/metrics') {
        request.response.write(jsonEncode({'cpu_load': 3, 'memory_usage': 40, 'temp': 48.0, 'temp_is_real': false, 'uptime': 99}));
      } else if (route == 'GET /api/hydra-info') {
        infoReads++;
        if (infoWorks) {
          request.response.write(jsonEncode({'remoteApiVersion': 2, 'appVersion': '0.9.1'}));
        } else {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        }
      } else if (route == 'GET /api/ecosystem/status') {
        ecosystemReads++;
        request.response.statusCode = ecosystemStatus;
        if (ecosystemStatus == 200) {
          request.response.write(jsonEncode({
            'available': true,
            'projects': [
              {'name': 'HYDRA-UMC-SERVER', 'family': 'Core', 'servicePort': 3000, 'live': true},
              {'name': 'HYDRA-UMC-SDK', 'family': 'Libraries'},
            ],
          }));
        }
      } else if (route == 'POST /api/logout') {
        request.response.write(jsonEncode({'success': true}));
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

class _FakeSpeech implements SpeechBridge {
  final List<Map<String, Object>> asked = [];
  SpeechOutcome outcome = const SpeechOutcome(SpeechStatus.ok, 'move the arm to zero');
  @override
  Future<SpeechOutcome> listen({required String languageTag, required bool onDeviceOnly, required int timeoutMs}) async {
    asked.add({'language': languageTag, 'onDeviceOnly': onDeviceOnly, 'timeoutMs': timeoutMs});
    return outcome;
  }

  @override
  Future<void> cancel() async {}
}

class _DenyingAlerts implements AlertsBridge {
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> show({required String id, required String title, required String body}) async {}
}

Future<(_Server, RobotViewModel, _FakeSpeech)> _signedIn({AlertsBridge? alerts}) async {
  SharedPreferences.setMockInitialValues({});
  final server = await _Server.start();
  addTearDown(server.close);
  final speech = _FakeSpeech();
  final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), speechBridge: speech, alertsBridge: alerts);
  addTearDown(vm.dispose);
  expect(await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x')), isTrue);
  return (server, vm, speech);
}

void main() {
  test('the ecosystem is read on demand, not twice in a row, and an old server reads as unavailable', () async {
    final (server, vm, _) = await _signedIn();
    final t0 = DateTime(2000);
    await vm.refreshEcosystem(now: t0);
    expect(vm.ecosystem.available, isTrue);
    expect(vm.ecosystem.projects.map((p) => p.name), ['HYDRA-UMC-SERVER', 'HYDRA-UMC-SDK']);
    expect(vm.ecosystemLoaded, isTrue);

    await vm.refreshEcosystem(now: t0.add(const Duration(milliseconds: 500)));
    expect(server.ecosystemReads, 1, reason: 'inside the minimum gap');

    server.ecosystemStatus = 404;
    await vm.refreshEcosystem(now: t0.add(const Duration(seconds: 10)));
    expect(server.ecosystemReads, 2);
    expect(vm.ecosystem.available, isFalse);
    expect(vm.isLoggedIn, isTrue, reason: 'a 404 is an old server, not a dead session');
  });

  test('signing out forgets the ecosystem and the link readings', () async {
    final (_, vm, _) = await _signedIn();
    await vm.refreshEcosystem(now: DateTime(2000));
    await vm.runDiagnostics();
    expect(vm.link.level, isNot(LinkLevel.unknown));
    vm.logout();
    expect(vm.ecosystem.projects, isEmpty);
    expect(vm.ecosystemLoaded, isFalse);
    expect(vm.link.level, LinkLevel.unknown);
  });

  test('the diagnostics probe the server, grade the link and give a report without secrets', () async {
    final (server, vm, _) = await _signedIn();
    final result = (await vm.runDiagnostics())!;
    expect(server.infoReads, greaterThanOrEqualTo(3));
    expect(result.latenciesMs, hasLength(3));
    expect(result.answeredMs, hasLength(3));
    expect(result.remoteApiVersion, 2);
    expect(result.serverAppVersion, '0.9.1');
    expect(result.scheme, 'http', reason: 'a loopback server without TLS');
    expect(result.trust, TrustMode.plainHttp);
    expect(result.level, LinkLevel.good);
    expect(result.websocket, isNotEmpty);
    final text = result.report();
    expect(text, contains('address: http://127.0.0.1:${server.port}'));
    expect(text.toLowerCase(), isNot(contains('token-1')));
    expect(text.toLowerCase(), isNot(contains('refresh')));
  });

  test('a server that does not answer the probe reads as a lost link', () async {
    final (server, vm, _) = await _signedIn();
    server.infoWorks = false;
    final result = (await vm.runDiagnostics())!;
    expect(result.answeredMs, isEmpty);
    expect(result.lost, 3);
    expect(result.level, LinkLevel.lost);
    expect(vm.link.blocksJog, isTrue);
  });

  test('dictation is off by default, keeps the audio on the phone unless allowed, and only returns a text', () async {
    final (_, vm, speech) = await _signedIn();
    expect(vm.dictationEnabled, isFalse);
    expect(vm.dictationOnline, isFalse);
    final outcome = await vm.dictate();
    expect(outcome.status, SpeechStatus.ok);
    expect(outcome.text, 'move the arm to zero');
    expect(speech.asked.single['onDeviceOnly'], isTrue);
    expect(speech.asked.single['timeoutMs'], isPositive);

    await vm.setDictationOnline(true);
    await vm.dictate();
    expect(speech.asked.last['onDeviceOnly'], isFalse);
  });

  test('the switches start off, are saved, and a refused notification permission leaves them off', () async {
    final (_, vm, _) = await _signedIn(alerts: _DenyingAlerts());
    expect((vm.jobAlertsEnabled, vm.liveActivityEnabled, vm.watchEnabled, vm.dictationEnabled), (false, false, false, false));
    expect(await vm.setJobAlerts(true), isFalse);
    expect(vm.jobAlertsEnabled, isFalse);
    await vm.setLiveActivity(true);
    await vm.setWatch(true);
    await vm.setDictation(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hydra_job_alerts'), isFalse);
    expect(prefs.getBool('hydra_live_activity'), isTrue);
    expect(prefs.getBool('hydra_watch_companion'), isTrue);
    expect(prefs.getBool('hydra_dictation'), isTrue);

    final second = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()));
    addTearDown(second.dispose);
    await second.init();
    expect((second.liveActivityEnabled, second.watchEnabled, second.dictationEnabled, second.jobAlertsEnabled), (true, true, true, false));
  });
}
