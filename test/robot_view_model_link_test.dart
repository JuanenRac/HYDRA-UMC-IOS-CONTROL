// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/robot_view_model_link_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The continuous jog, the pairing by link, the alerts and relays of the watch and the Work selector through the view model,
// against a real local dart:io HttpServer (no robot, no mocked client): every switch starts as the contract says, nothing is
// kept before the person confirms a pairing, a Work is loaded but never played, and a STOP ends a held jog.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/models/server_info.dart';
import 'package:hydra_umc_control/network/auth_prefs.dart';
import 'package:hydra_umc_control/network/native_bridges.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
import 'package:hydra_umc_control/state/robot_view_model.dart';
import 'package:hydra_umc_control/network/tls_settings.dart';

class _FakeSecureBackend implements SecureTokenBackend {
  final Map<String, String> store = {};
  @override
  Future<void> write(String key, String value) async => store[key] = value;
  @override
  Future<String?> read(String key) async => store[key];
  @override
  Future<void> delete(String key) async => store.remove(key);
}

class _FakeWatch implements WatchBridge {
  final List<Map<String, Object>> alerts = [];
  bool reachable = true;
  @override
  Future<bool> isReachable() async => reachable;
  @override
  Future<void> sendStatus(Map<String, Object> status) async {}
  @override
  void listenForStop(bool Function(DateTime requestedAt) onStop) {}
  @override
  Future<bool> sendAlert(Map<String, Object> alert) async {
    if (reachable) alerts.add(alert);
    return reachable;
  }

  @override
  void listenForRelays({
    required Future<void> Function(Map<dynamic, dynamic> heartbeat) onPresence,
    required Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm) onVoiceConfirm,
  }) {}
}

class _FakePairing implements PairingBridge {
  String? pending;
  @override
  Future<String?> takePending() async {
    final link = pending;
    pending = null;
    return link;
  }

  @override
  void listen(void Function(String link) onLink) {}
}

class _Server {
  final HttpServer http;
  bool playing = false;
  int presenceStatus = 200;
  final List<Map<String, dynamic>> commands = [];
  final List<Map<String, dynamic>> presence = [];
  final List<Map<String, dynamic>> confirms = [];
  final List<String> reads = [];

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
      } else if (route == 'GET /api/hydra-info') {
        request.response.write(jsonEncode({'remoteApiVersion': 2, 'appVersion': '0.8.2.1'}));
      } else if (route == 'POST /api/robot/1/command') {
        commands.add(json);
        request.response.write(jsonEncode({'success': true}));
      } else if (route == 'GET /WORKS/Robot1/index.json') {
        reads.add(route);
        request.response.write(jsonEncode(['cut.json', 'bad.json', '../evil.json']));
      } else if (route == 'GET /WORKS/Robot1/cut.json') {
        reads.add(route);
        request.response.write(jsonEncode([
          {'x': 1, 'y': 2, 'z': 3, 'junk': 'dropped'},
          {'x': 4, 'y': 5, 'z': 6},
        ]));
      } else if (route == 'GET /WORKS/Robot1/bad.json') {
        reads.add(route);
        request.response.write(jsonEncode({'not': 'a list'}));
      } else if (route == 'POST /api/operator/presence') {
        presence.add(json);
        request.response.statusCode = presenceStatus;
        request.response.write(jsonEncode({'ok': presenceStatus == 200}));
      } else if (route == 'POST /api/voice/confirm') {
        confirms.add(json);
        request.response.write(jsonEncode({
          'requestId': 'r-2',
          'text': 'Done',
          'level': 'INFO',
          'speak': true,
          'requiresConfirmation': false,
          'confirmationToken': 'short',
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  }

  static Future<_Server> start() async => _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  int get port => http.port;
  Future<void> close() => http.close(force: true);

  int count(String command) => commands.where((c) => c['command'] == command).length;
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 6)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<(_Server, RobotViewModel, _FakeWatch)> _signedIn({bool playing = false, String? pendingLink}) async {
  SharedPreferences.setMockInitialValues({});
  final server = await _Server.start();
  server.playing = playing;
  addTearDown(server.close);
  final watch = _FakeWatch();
  final vm = RobotViewModel(
    authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()),
    watchBridge: watch,
    pairingBridge: _FakePairing()..pending = pendingLink,
  );
  addTearDown(vm.dispose);
  final ok = await vm.login(ServerInfo(host: '127.0.0.1', port: server.port, username: 'alice', password: 'x'));
  expect(ok, isTrue);
  expect(vm.selectedRobot, isNotNull);
  await _until(() => vm.connectionStatus == 'connected');
  return (server, vm, watch);
}

void main() {
  final fp = 'cd' * 32;

  test('every switch starts as the contract says', () async {
    SharedPreferences.setMockInitialValues({});
    final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
    addTearDown(vm.dispose);
    expect(vm.deadMan.enabled, isFalse);
    expect(vm.deadMan.indicator, isTrue);
    expect(vm.deadMan.blockOnBadLink, isTrue);
    expect(vm.pairingEnabled, isFalse);
    expect(vm.watchAlertsEnabled, isTrue);
    expect(vm.presenceRelayEnabled, isFalse);
    expect(vm.voiceConfirmRelayEnabled, isFalse);
  });

  test('the switches are kept and read again by the next start', () async {
    SharedPreferences.setMockInitialValues({});
    final first = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
    await first.setDeadManEnabled(true);
    await first.setLinkBlockOnBadLink(false);
    await first.setLinkIndicator(false);
    await first.setPairingEnabled(true);
    await first.setWatchAlertsEnabled(false);
    await first.setPresenceRelayEnabled(true);
    await first.setVoiceConfirmRelayEnabled(true);
    first.dispose();

    final second = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
    addTearDown(second.dispose);
    await second.init();
    expect(second.deadMan.enabled, isTrue);
    expect(second.deadMan.blockOnBadLink, isFalse);
    expect(second.deadMan.indicator, isFalse);
    expect(second.pairingEnabled, isTrue);
    expect(second.watchAlertsEnabled, isFalse);
    expect(second.presenceRelayEnabled, isTrue);
    expect(second.voiceConfirmRelayEnabled, isTrue);
  });

  group('pairing by link', () {
    test('while it is off nothing is read, and the person is told', () async {
      SharedPreferences.setMockInitialValues({});
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
      addTearDown(vm.dispose);
      expect(await vm.receivePairing('hydra-umc://pair?host=a.local&port=3000'), isTrue);
      expect(vm.pairingOffer, isNull);
      expect(vm.lastError!.kind, HydraErrorKind.pairingOff);
      expect(await vm.receivePairing('https://example.com'), isFalse, reason: 'not a pairing link at all');
    });

    test('an offer is only shown: nothing is kept before the person confirms', () async {
      SharedPreferences.setMockInitialValues({});
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
      addTearDown(vm.dispose);
      await vm.setPairingEnabled(true);
      await vm.receivePairing('hydra-umc://pair?host=hydra.local&port=3443&fp=$fp&name=Cell');
      expect(vm.pairingOffer!.host, 'hydra.local');
      expect(vm.pairingOffer!.name, 'Cell');
      expect(vm.tlsSettings.pinnedFingerprint, isEmpty);
      expect(vm.pairedHost, isNull);
      vm.dismissPairing();
      expect(vm.pairingOffer, isNull);
      expect(vm.tlsSettings.pinnedFingerprint, isEmpty);
    });

    test('confirming requires TLS, pins the certificate and hands the address to the sign-in', () async {
      SharedPreferences.setMockInitialValues({});
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
      addTearDown(vm.dispose);
      await vm.setTlsSettings(TlsSettings(allowPlainHttp: true, pinnedFingerprint: 'ab' * 32));
      await vm.setPairingEnabled(true);
      await vm.receivePairing('hydra-umc://pair?host=hydra.local&port=3443&fp=$fp');
      await vm.confirmPairing();
      expect(vm.tlsSettings.allowPlainHttp, isFalse);
      expect(vm.tlsSettings.allowPlainRemote, isFalse);
      expect(vm.tlsSettings.pinnedFingerprint, fp);
      expect(vm.pairedHost, 'hydra.local');
      expect(vm.pairedPort, 3443);
      expect(vm.pairingOffer, isNull);
    });

    test('a link without a fingerprint changes no TLS setting', () async {
      SharedPreferences.setMockInitialValues({});
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
      addTearDown(vm.dispose);
      await vm.setPairingEnabled(true);
      await vm.receivePairing('hydra-umc://pair?host=hydra.local&port=3000');
      await vm.confirmPairing();
      expect(vm.tlsSettings, const TlsSettings());
      expect(vm.pairedPort, 3000);
    });

    test('a bad link says why and offers nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: _FakePairing());
      addTearDown(vm.dispose);
      await vm.setPairingEnabled(true);
      await vm.receivePairing('hydra-umc://pair?host=a.local&port=99999');
      expect(vm.pairingOffer, isNull);
      expect(vm.lastError!.kind, HydraErrorKind.pairingProblem);
      expect(await vm.readPastedPairing('just some text'), isFalse);
      expect(vm.lastError!.params['problem'], 'notAPairingLink');
    });

    test('the link that opened the app is read once the switches are loaded', () async {
      SharedPreferences.setMockInitialValues({'hydra_flag_pairing': true});
      final bridge = _FakePairing()..pending = 'hydra-umc://pair?host=hydra.local&port=3000';
      final vm = RobotViewModel(authPrefs: AuthPrefs(secureBackend: _FakeSecureBackend()), pairingBridge: bridge);
      addTearDown(vm.dispose);
      await vm.init();
      expect(vm.pairingOffer!.host, 'hydra.local');
    });
  });

  group('the continuous jog', () {
    test('while the switch is off a press sends nothing', () async {
      final (server, vm, _) = await _signedIn();
      await vm.deadMan.press(1, 'robot', 'x', 1);
      expect(server.commands, isEmpty);
      expect(vm.lastError!.kind, HydraErrorKind.deadManBlocked);
    });

    test('with the switch on it sends start, heartbeats and stop, and a STOP ends it', () async {
      final (server, vm, _) = await _signedIn();
      await vm.setDeadManEnabled(true);
      await vm.deadMan.press(1, 'robot', 'x', 1);
      await _until(() => server.count('jogHeartbeat') >= 3);
      expect(server.count('jogStart'), 1);
      expect(server.count('jogHeartbeat'), greaterThanOrEqualTo(3));
      expect(vm.deadMan.held, {1});

      vm.sendCommand('stop');
      await _until(() => server.count('jogStop') >= 1);
      expect(server.count('jogStop'), 1);
      expect(vm.deadMan.held, isEmpty);
      final heartbeats = server.count('jogHeartbeat');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(server.count('jogHeartbeat'), heartbeats, reason: 'no heartbeat after the stop');
    });

    test('leaving the app ends it', () async {
      final (server, vm, _) = await _signedIn();
      await vm.setDeadManEnabled(true);
      await vm.deadMan.press(1, 'robot', 'y', -1);
      await _until(() => server.count('jogHeartbeat') >= 1);
      vm.pauseForBackground();
      await _until(() => server.count('jogStop') >= 1);
      expect(server.count('jogStop'), 1);
      expect(vm.deadMan.held, isEmpty);
    });

    test('a robot that is playing cannot be jogged continuously', () async {
      final (server, vm, _) = await _signedIn(playing: true);
      await vm.setDeadManEnabled(true);
      await vm.deadMan.press(1, 'robot', 'x', 1);
      expect(server.commands, isEmpty);
      expect(vm.lastError!.params['block'], 'moving');
    });

    test('the link is measured while connected and a slow link blocks the jog', () async {
      final (_, vm, _) = await _signedIn();
      await _until(() => vm.link.lastMs != null);
      expect(vm.link.lastMs, isNotNull);
      await vm.setDeadManEnabled(true);
      vm.link.record(RobotCommandContract.linkBlockRttMs);
      expect(vm.deadMan.blockOf(1).name, 'badLink');
      await vm.setLinkBlockOnBadLink(false);
      expect(vm.deadMan.blockOf(1).name, 'none');
    });
  });

  group('the watch', () {
    test('an alert is sent when a robot goes offline, in the language of the app', () async {
      final (_, vm, watch) = await _signedIn();
      await vm.setWatch(true);
      await vm.watchAlertsTick(); // the first look only learns the starting point
      vm.selectedRobot!.raw['online'] = false;
      await vm.watchAlertsTick();
      expect(watch.alerts, hasLength(1));
      expect(watch.alerts.single['type'], 'alert');
      expect(watch.alerts.single['severity'], 'WARNING');
      expect(watch.alerts.single['message'], 'Robot 1 went offline');
    });

    test('nothing is sent while the alerts or the Apple Watch option are off', () async {
      final (_, vm, watch) = await _signedIn();
      await vm.watchAlertsTick();
      vm.selectedRobot!.raw['online'] = false;
      await vm.watchAlertsTick();
      expect(watch.alerts, isEmpty, reason: 'the Apple Watch option is off');
      await vm.setWatch(true);
      await vm.setWatchAlertsEnabled(false);
      vm.selectedRobot!.raw['enabled'] = false;
      await vm.watchAlertsTick();
      expect(watch.alerts, isEmpty);
    });

    test('the presence relay is off by default, then passes the heartbeat on and goes quiet on a 404', () async {
      final (server, vm, _) = await _signedIn();
      final beat = {'type': 'presence_heartbeat', 'sequence': 1, 'intervalSeconds': 10, 'state': 'PRESENT'};
      await vm.relayPresence(beat);
      expect(server.presence, isEmpty);

      await vm.setPresenceRelayEnabled(true);
      await vm.relayPresence(beat);
      await vm.relayPresence({...beat, 'sequence': 4});
      expect(server.presence, hasLength(2));
      expect(server.presence.last['missed'], 2);
      expect(server.presence.last['state'], 'PRESENT');

      server.presenceStatus = 404;
      await vm.relayPresence({...beat, 'sequence': 5});
      await vm.relayPresence({...beat, 'sequence': 6});
      expect(server.presence, hasLength(3), reason: 'after a 404 the relay stays quiet');
      await vm.relayPresence({'type': 'presence_heartbeat', 'sequence': -3, 'intervalSeconds': 10});
      expect(server.presence, hasLength(3));
    });

    test('the confirmation relay is off by default, then passes the tap on and drops a token the watch would refuse', () async {
      final (server, vm, _) = await _signedIn();
      final confirm = {'type': 'voice_confirm', 'requestId': 'r-2', 'confirms': 'r-1', 'confirmationToken': 'abcdefghijklmnop1234'};
      final off = await vm.relayVoiceConfirm(confirm);
      expect(server.confirms, isEmpty);
      expect(off!['requestId'], 'r-2');
      expect(off['requiresConfirmation'], false);

      await vm.setVoiceConfirmRelayEnabled(true);
      final reply = await vm.relayVoiceConfirm(confirm);
      expect(server.confirms, hasLength(1));
      expect(server.confirms.single['confirmationToken'], 'abcdefghijklmnop1234');
      expect(reply!['text'], 'Done');
      expect(reply.containsKey('confirmationToken'), isFalse, reason: 'the server token was too short for the watch');
      expect(await vm.relayVoiceConfirm({'type': 'voice_confirm'}), isNull);
    });
  });

  group('the Work selector', () {
    test('lists the folder of the robot, keeps only safe names and loads one with trajectory, never a play', () async {
      final (server, vm, _) = await _signedIn();
      expect(vm.workFolderOf(1), 'WORKS/Robot1');
      await vm.loadWorkList(1);
      expect(vm.workFiles, ['bad.json', 'cut.json']);

      await vm.selectWork(1, 'cut.json');
      await _until(() => server.count('trajectory') >= 1);
      final command = server.commands.single;
      expect(command['command'], 'trajectory');
      expect(command['params']['selectedWorkFile'], 'cut.json');
      expect((command['params']['points'] as List), hasLength(2));
      expect((command['params']['points'] as List).first.containsKey('junk'), isFalse);
      expect(server.count('play'), 0);
      expect(vm.selectedWorkOf(1), 'cut.json');
    });

    test('a file that is not a list of points is refused and nothing is sent', () async {
      final (server, vm, _) = await _signedIn();
      await vm.selectWork(1, 'bad.json');
      expect(server.commands, isEmpty);
      expect(vm.lastError!.kind, HydraErrorKind.workInvalidFile);
    });

    test('a robot that is playing is refused before anything is read', () async {
      final (server, vm, _) = await _signedIn(playing: true);
      await vm.selectWork(1, 'cut.json');
      expect(server.reads, isEmpty);
      expect(server.commands, isEmpty);
      expect(vm.lastError!.kind, HydraErrorKind.workBlocked);
      expect(vm.lastError!.params['block'], 'playing');
    });

    test('an unsafe file name is refused', () async {
      final (server, vm, _) = await _signedIn();
      await vm.selectWork(1, '../evil.json');
      expect(server.reads, isEmpty);
      expect(vm.lastError!.kind, HydraErrorKind.workLoadFailed);
    });
  });
}
