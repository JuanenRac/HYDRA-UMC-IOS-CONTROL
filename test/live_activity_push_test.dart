// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/live_activity_push_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Handing the token of the Live Activity to the server, on the Dart VM (no iPhone, no Xcode):
//   - the option starts off, and an activity started with it off never asks the system for a token;
//   - with it on, the token the system gives is registered once for the robot on the card, and taken back when the activity
//     ends, when the option is turned off and when a new token replaces it;
//   - a token that arrives with nothing running, with the option off, or twice is dropped; a server that says no or fails never
//     raises an error and never stops the card;
//   - the requests to the server have the shape of the contract (POST and DELETE /api/push/live-activities);
//   - the Swift half passes the token to the Dart side by the call the Dart side listens to.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hydra_umc_control/models/ios_feature_contract.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/network/native_bridges.dart';
import 'package:hydra_umc_control/state/external_surfaces.dart';
import 'package:hydra_umc_control/util/job_alerts.dart';

class _Alerts implements AlertsBridge {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show({required String id, required String title, required String body}) async {}
}

class _Watch implements WatchBridge {
  @override
  Future<bool> isReachable() async => false;
  @override
  Future<void> sendStatus(Map<String, Object> status) async {}
  @override
  void listenForStop(bool Function(DateTime requestedAt) onStop) {}
  @override
  Future<bool> sendAlert(Map<String, Object> alert) async => false;
  @override
  void listenForRelays({
    required Future<void> Function(Map<dynamic, dynamic> heartbeat) onPresence,
    required Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm) onVoiceConfirm,
  }) {}
}

class _Live implements LiveActivityBridge {
  final List<String> calls = [];
  final List<bool> pushRequests = [];
  void Function(String token)? emit;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> start(Map<String, Object> content, {bool pushToken = false}) async {
    calls.add('start');
    pushRequests.add(pushToken);
    return true;
  }

  @override
  Future<void> update(Map<String, Object> content) async => calls.add('update');
  @override
  Future<void> end(Map<String, Object> content, {int dismissAfterSeconds = 0}) async => calls.add('end');
  @override
  void listenForPushToken(void Function(String token) onToken) => emit = onToken;
}

RobotSnapshot _robot({String id = '7', bool playing = false, bool finished = false, int step = -1}) =>
    RobotSnapshot(id: id, name: 'Parol6', playing: playing, finished: finished, activeStep: step, totalSteps: 10);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime(2000, 1, 1, 12);

  group('the Live Activity token and the server', () {
    late _Live live;
    late ExternalSurfaces surfaces;
    late List<(String, String)> registered;
    late List<String> forgotten;
    var accept = true;
    var raise = false;

    setUp(() {
      live = _Live();
      registered = [];
      forgotten = [];
      accept = true;
      raise = false;
      surfaces = ExternalSurfaces(alerts: _Alerts(), liveActivity: live, watch: _Watch(), clock: () => t0)
        ..registerActivityToken = (token, robotId) async {
          if (raise) throw StateError('server down');
          registered.add((token, robotId));
          return accept;
        }
        ..forgetActivityToken = (token) async {
          if (raise) throw StateError('server down');
          forgotten.add(token);
        };
      addTearDown(surfaces.dispose);
    });

    test('the contract starts it off', () {
      expect(LiveActivityContract.serverPushEnabledByDefault, isFalse);
      expect(surfaces.liveActivityPushEnabled, isFalse);
    });

    test('with the option off the system is not asked for a token and a stray one is dropped', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      expect(live.pushRequests, [false]);
      live.emit!('aa');
      await _settle();
      expect(registered, isEmpty);
    });

    test('with the option on the token is asked for and registered once for the robot on the card', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(id: '12', playing: true, step: 0)], connected: true);
      expect(live.pushRequests, [true]);
      live.emit!('0a0b');
      await _settle();
      live.emit!('0a0b');
      await _settle();
      expect(registered, [('0a0b', '12')]);
      expect(forgotten, isEmpty);
    });

    test('a new token replaces the old one, which is taken back first', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      live.emit!('aa');
      await _settle();
      live.emit!('bb');
      await _settle();
      expect(registered.map((r) => r.$1), ['aa', 'bb']);
      expect(forgotten, ['aa']);
    });

    test('the token is taken back before the activity ends, when the job finishes, the session ends or the option is turned off', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      live.emit!('aa');
      await _settle();
      await surfaces.onState([_robot(finished: true)], connected: true);
      expect(forgotten, ['aa']);
      expect(live.calls, ['start', 'end']);

      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      live.emit!('bb');
      await _settle();
      await surfaces.onSessionEnd();
      expect(forgotten, ['aa', 'bb']);

      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      live.emit!('cc');
      await _settle();
      await surfaces.setLiveActivityPush(false);
      expect(forgotten, ['aa', 'bb', 'cc']);
      expect(surfaces.liveActivityPushEnabled, isFalse);
    });

    test('a token that arrives after the activity ended is dropped', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      await surfaces.onSessionEnd();
      live.emit!('late');
      await _settle();
      expect(registered, isEmpty);
    });

    test('a server that says no or fails never raises, and the next token can try again', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      accept = false;
      live.emit!('aa');
      await _settle();
      expect(registered.length, 1);
      accept = true;
      live.emit!('aa');
      await _settle();
      expect(registered.length, 2, reason: 'a token the server did not take is not remembered as taken');
      raise = true;
      live.emit!('bb');
      await _settle();
      await surfaces.setLiveActivityPush(false);
      expect(live.calls, ['start']);
    });

    test('without a way to reach the server the token is not even asked for', () async {
      final bare = _Live();
      final plain = ExternalSurfaces(alerts: _Alerts(), liveActivity: bare, watch: _Watch(), clock: () => t0);
      addTearDown(plain.dispose);
      await plain.setLiveActivity(true);
      await plain.setLiveActivityPush(true);
      await plain.onState([_robot(playing: true, step: 0)], connected: true);
      expect(bare.pushRequests, [false]);
    });

    test('a robot without an id never asks for a token', () async {
      await surfaces.setLiveActivity(true);
      await surfaces.setLiveActivityPush(true);
      await surfaces.onState([_robot(id: '', playing: true, step: 0)], connected: true);
      expect(live.pushRequests, [false]);
    });

    test('a restored choice applies to the next activity', () async {
      surfaces.restoreLiveActivity(true);
      surfaces.restoreLiveActivityPush(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      expect(live.pushRequests, [true]);
    });
  });

  group('the requests to the server', () {
    test('POST hands over the token and the robot, DELETE takes the token back', () async {
      final seen = <http.Request>[];
      final client = HydraApiClient('127.0.0.1', 3000, client: MockClient((request) async {
        seen.add(request);
        return http.Response(request.method == 'POST' ? '{"registered":true}' : '{"removed":true}', 200);
      }));
      client.authToken = 'tok.en';
      await client.postLiveActivity('0a0b', '12');
      await client.deleteLiveActivity('0a0b');
      expect(seen.map((r) => '${r.method} ${r.url.path}'), ['POST /api/push/live-activities', 'DELETE /api/push/live-activities/0a0b']);
      expect(jsonDecode(seen.first.body), {'activityToken': '0a0b', 'robotId': '12'});
      for (final request in seen) {
        expect(request.headers['Authorization'], isNotNull);
      }
    });

    test('a server with the option off answers 404, which reads as not found', () async {
      final client = HydraApiClient('127.0.0.1', 3000, client: MockClient((request) async => http.Response('', 404)));
      client.authToken = 'tok.en';
      await expectLater(client.postLiveActivity('aa', '1'), throwsA(isA<HydraApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue)));
    });

    test('the token is encoded in the path', () async {
      Uri? asked;
      final client = HydraApiClient('127.0.0.1', 3000, client: MockClient((request) async {
        asked = request.url;
        return http.Response('{}', 200);
      }));
      client.authToken = 'tok.en';
      await client.deleteLiveActivity('a/b c');
      expect(asked!.path, '/api/push/live-activities/a%2Fb%20c');
    });
  });

  group('the Swift half', () {
    test('passes the token to the Dart side by the call the Dart side listens to', () {
      final swift = File('ios/Runner/LiveActivityBridge.swift').readAsStringSync();
      final dart = File('lib/network/native_bridges.dart').readAsStringSync();
      expect(swift, contains('invokeMethod("pushToken"'));
      expect(dart, contains("call.method == 'pushToken'"));
      expect(swift, contains('pushTokenUpdates'));
      expect(swift, contains('"pushToken"'));
      expect(swift, contains('pushType: wantsPush ? .token : nil'), reason: 'the token is only asked for when the Dart side wants it');
    });

    test('the settings screen has the switch, off unless the Live Activity is on', () {
      final screen = File('lib/ui/settings_screen.dart').readAsStringSync();
      expect(screen, contains("Key('settings-live-activity-push')"));
      expect(screen, contains('onChanged: vm.liveActivityEnabled ?'));
    });
  });
}
