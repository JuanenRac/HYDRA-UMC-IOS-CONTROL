// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/watch_alerts_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The alerts the phone pushes to the watch (what is worth one, and how many) and what the watch passes to the phone to relay
// (presence and the second tap of a spoken order).
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/util/watch_alerts.dart';
import 'package:hydra_umc_control/util/watch_relay.dart';

void main() {
  var now = DateTime.fromMillisecondsSinceEpoch(1000000);
  late WatchAlertRules rules;

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(1000000);
    rules = WatchAlertRules(clock: () => now);
  });

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  WatchAlertRobot robot(int id, {bool online = true, bool enabled = true, bool playing = false}) =>
      WatchAlertRobot('$id', 'Arm $id', online, enabled, playing);

  WatchAlertInput input({List<WatchAlertRobot>? robots, bool connected = true, WatchAlertStop stop = WatchAlertStop.none}) =>
      WatchAlertInput(connected: connected, robots: robots ?? [robot(1)], stop: stop);

  List<WatchAlertKind> kinds(List<WatchAlertEvent> events) => [for (final e in events) e.kind];

  group('the rules', () {
    test('the first observation only learns the starting point', () {
      expect(rules.observe(input(robots: [robot(1, online: false)])), isEmpty);
      expect(rules.observe(input(robots: [robot(1, online: false)])), isEmpty);
    });

    test('a connection that never existed is not a lost connection', () {
      rules.observe(input(connected: false));
      advance(60000);
      expect(rules.observe(input(connected: false)), isEmpty);
    });

    test('a lost connection is announced once after the wait and again when it comes back', () {
      rules.observe(input());
      advance(1000);
      expect(rules.observe(input(connected: false)), isEmpty);
      advance(9000);
      expect(rules.observe(input(connected: false)), isEmpty, reason: 'not yet 10 s');
      advance(2000);
      final lost = rules.observe(input(connected: false)).single;
      expect(lost.kind, WatchAlertKind.connectionLost);
      expect(lost.severity, WatchAlertSeverity.warning);
      advance(5000);
      expect(rules.observe(input(connected: false)), isEmpty, reason: 'announced only once');
      advance(5000);
      expect(kinds(rules.observe(input())), [WatchAlertKind.connectionRestored]);
    });

    test('a connection lost while a robot was running is critical', () {
      rules.observe(input(robots: [robot(1, playing: true)]));
      advance(1000);
      rules.observe(input(robots: const [], connected: false));
      advance(11000);
      expect(rules.observe(input(robots: const [], connected: false)).single.severity, WatchAlertSeverity.critical);
    });

    test('a robot that goes offline while running is critical, otherwise a warning', () {
      rules.observe(input(robots: [robot(1, playing: true), robot(2)]));
      advance(1000);
      final events = rules.observe(input(robots: [robot(1, online: false), robot(2, online: false)]));
      expect(events.firstWhere((e) => e.robotName == 'Arm 1').severity, WatchAlertSeverity.critical);
      expect(events.firstWhere((e) => e.robotName == 'Arm 2').severity, WatchAlertSeverity.warning);
    });

    test('a robot put in safe mode is a warning', () {
      rules.observe(input());
      advance(1000);
      final event = rules.observe(input(robots: [robot(1, enabled: false)])).single;
      expect(event.kind, WatchAlertKind.robotSafeMode);
      expect(event.robotName, 'Arm 1');
    });

    test('a stop the server did not confirm is critical and the confirmation is information', () {
      rules.observe(input());
      advance(1000);
      rules.observe(input(stop: WatchAlertStop.sending));
      advance(1000);
      final bad = rules.observe(input(stop: WatchAlertStop.notConfirmed)).single;
      expect(bad.kind, WatchAlertKind.stopNotConfirmed);
      expect(bad.severity, WatchAlertSeverity.critical);
      advance(5000);
      final done = rules.observe(input(stop: WatchAlertStop.done)).single;
      expect(done.kind, WatchAlertKind.stopConfirmed);
      expect(done.severity, WatchAlertSeverity.info);
    });

    test('a stop that is confirmed with nothing before it is not announced', () {
      rules.observe(input());
      advance(1000);
      expect(rules.observe(input(stop: WatchAlertStop.done)), isEmpty);
    });

    test('the same event is not repeated within the dedupe window', () {
      rules.observe(input());
      advance(1000);
      expect(rules.observe(input(robots: [robot(1, enabled: false)])), hasLength(1));
      advance(1000);
      rules.observe(input());
      advance(1000);
      expect(rules.observe(input(robots: [robot(1, enabled: false)])), isEmpty, reason: 'same robot, same event, 3 s later');
      advance(40000);
      rules.observe(input());
      advance(1000);
      expect(rules.observe(input(robots: [robot(1, enabled: false)])), hasLength(1));
    });

    test('alerts that are not critical are spaced and capped', () {
      List<WatchAlertRobot> ten({bool Function(int)? enabled}) => [for (var i = 1; i <= 10; i++) robot(i, enabled: enabled?.call(i) ?? true)];
      rules.observe(input(robots: ten()));
      advance(1000);
      // ten robots enter safe mode together: what is found together goes out together, up to the cap of six a minute
      expect(rules.observe(input(robots: ten(enabled: (_) => false))), hasLength(6));
      advance(1000);
      rules.observe(input(robots: ten()));
      advance(4000);
      expect(rules.observe(input(robots: ten(enabled: (i) => i != 7))), isEmpty, reason: 'inside the same minute the cap still holds');
      advance(61000);
      rules.observe(input(robots: ten()));
      advance(1000);
      expect(rules.observe(input(robots: ten(enabled: (i) => i != 7))), hasLength(1));
    });

    test('a critical alert is never held back by the cap', () {
      rules.observe(input(robots: [for (var i = 1; i <= 8; i++) robot(i, playing: i == 8)]));
      advance(1000);
      final events = rules.observe(input(robots: [for (var i = 1; i <= 8; i++) robot(i, enabled: false, online: i != 8)]));
      expect(events.any((e) => e.severity == WatchAlertSeverity.critical && e.robotName == 'Arm 8'), isTrue);
      expect(events, hasLength(6));
    });

    test('a new session starts over', () {
      rules.observe(input(robots: [robot(1, online: false)]));
      rules.reset();
      expect(rules.observe(input()), isEmpty);
    });
  });

  group('the message', () {
    test('is what the watch accepts and long text is cut', () {
      final map = WatchAlert.of(WatchAlertSeverity.critical, 'Robot stopped').toMap();
      expect(map, {'type': 'alert', 'severity': 'CRITICAL', 'message': 'Robot stopped'});
      final long = WatchAlert.of(WatchAlertSeverity.info, 'x' * 900);
      expect(long.message.length, RobotCommandContract.watchAlertsMessageMax);
      expect(long.message.endsWith('…'), isTrue);
      expect(WatchAlert.of(WatchAlertSeverity.info, '   ').message, '!');
      expect(() => WatchAlert(WatchAlertSeverity.info, ' '), throwsArgumentError);
    });
  });

  group('what the watch asks the phone to relay', () {
    test('the presence heartbeat is read, bounded and counted', () {
      final beat = WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': 5, 'intervalSeconds': 10, 'state': 'PRESENT'});
      expect(beat.left, isFalse);
      expect(beat.toServerJson(2), containsPair('missed', 2));
      expect(beat.toServerJson(0)['state'], 'PRESENT');
      expect(WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': 6, 'intervalSeconds': 10, 'state': 'LEFT'}).left, isTrue);
      expect(() => WatchPresenceHeartbeat.fromMap({'type': 'other', 'sequence': 1, 'intervalSeconds': 10}), throwsArgumentError);
      expect(() => WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': 1, 'intervalSeconds': 61}), throwsArgumentError);
      expect(() => WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': -1, 'intervalSeconds': 10}), throwsArgumentError);
      expect(() => WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': 1, 'intervalSeconds': 10, 'state': 'AWAY'}), throwsArgumentError);
      expect(() => WatchPresenceHeartbeat.fromMap({'type': 'presence_heartbeat', 'sequence': 1, 'intervalSeconds': 10, 'protocolVersion': 2}), throwsArgumentError);
    });

    test('the tracker counts the heartbeats that never arrived', () {
      WatchPresenceHeartbeat beat(int s) => WatchPresenceHeartbeat(sequence: s, intervalSeconds: 10, left: false);
      final tracker = WatchPresenceTracker();
      expect(tracker.onHeartbeat(beat(4)), 0);
      expect(tracker.onHeartbeat(beat(5)), 0);
      expect(tracker.onHeartbeat(beat(9)), 3);
      expect(tracker.onHeartbeat(beat(9)), 0, reason: 'a repeat');
      expect(tracker.onHeartbeat(beat(1)), 0, reason: 'the counter of the watch started over');
      tracker.reset();
      expect(tracker.onHeartbeat(beat(50)), 0);
    });

    test('the confirmation of a spoken order is checked and its token never printed', () {
      const token = 'abcdefghijklmnop1234';
      final confirm = WatchVoiceConfirm.fromMap({'type': 'voice_confirm', 'requestId': 'r-1', 'confirms': 'r-0', 'confirmationToken': token});
      expect(confirm.toServerJson()['confirmationToken'], token);
      expect(confirm.toString().contains(token), isFalse);
      expect(() => WatchVoiceConfirm.fromMap({'type': 'voice_confirm', 'requestId': 'bad id', 'confirms': 'r-0', 'confirmationToken': token}), throwsArgumentError);
      expect(() => WatchVoiceConfirm.fromMap({'type': 'voice_confirm', 'requestId': 'r-1', 'confirms': 'r-0', 'confirmationToken': 'short'}), throwsArgumentError);
      expect(() => WatchVoiceConfirm.fromMap({'type': 'voice_confirm', 'requestId': 'r-1'}), throwsArgumentError);
      expect(WatchVoiceConfirm.isValidToken('x' * (RobotCommandContract.voiceConfirmTokenMax + 1)), isFalse);
    });

    test('the relays are off by default and the alerts on', () {
      expect(RobotCommandContract.presenceRelayEnabledByDefault, isFalse);
      expect(RobotCommandContract.voiceConfirmEnabledByDefault, isFalse);
      expect(RobotCommandContract.watchAlertsEnabledByDefault, isTrue);
    });
  });
}
