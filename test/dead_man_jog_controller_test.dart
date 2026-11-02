// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/dead_man_jog_controller_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The screen-facing side of the continuous jog against a fake server and a fake clock: the switch that is off by default, the
// refusals with their phrases, the stop in every way a held control can end, and the link meter that blocks the jog.
// =============================================================================


import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/state/dead_man_jog_controller.dart';
import 'package:hydra_umc_control/state/hydra_error.dart';
import 'package:hydra_umc_control/util/dead_man_jog.dart';
import 'package:hydra_umc_control/util/link_health.dart';

class _Fixture {
  _Fixture(FakeAsync async) {
    controller = DeadManJogController(
      poster: (robotId, payload, {required urgent, ifMatch}) async {
        final command = payload['command'] as String;
        commands.add(command);
        if (command == RobotCommandContract.jogStart && startError != null) throw startError!;
        if (command == RobotCommandContract.jogHeartbeat && heartbeatError != null) throw heartbeatError!;
        return {};
      },
      pinger: () async {
        if (pingFails) throw HydraApiException('no answer');
        return pingMs;
      },
      situation: (robotId, {required switchedOn, required alreadyRunning, required linkBlocks, required serverSupports}) => DeadManSituation(
        switchedOn: switchedOn,
        connected: connected,
        robotOnline: true,
        robotEnabled: true,
        robotPlaying: robotPlaying,
        stopInProgress: false,
        needsArming: false,
        role: 'operator',
        linkBlocks: linkBlocks,
        alreadyRunning: alreadyRunning,
        serverSupports: serverSupports,
      ),
      say: said.add,
      clock: () => async.elapsed.inMilliseconds,
      link: LinkHealth(clock: () => DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds)),
    );
  }

  late final DeadManJogController controller;
  final List<String> commands = [];
  final List<HydraError?> said = [];
  int pingMs = 20;
  bool pingFails = false;
  bool robotPlaying = false;
  bool connected = true;
  Object? startError;
  Object? heartbeatError;

  int count(String command) => commands.where((c) => c == command).length;
}

void _scenario(void Function(FakeAsync async, _Fixture f) body) {
  fakeAsync((async) {
    final f = _Fixture(async);
    body(async, f);
    f.controller.dispose();
    async.flushMicrotasks();
  });
}

void main() {
  test('the jog starts off, the indicator and the block on a bad link start on', () {
    _scenario((async, f) {
      expect(f.controller.enabled, isFalse);
      expect(f.controller.indicator, isTrue);
      expect(f.controller.blockOnBadLink, isTrue);
      expect(f.controller.velocity, RobotCommandContract.deadManVelocityDefault.toDouble());
      expect(f.controller.blockOf(1), DeadManBlock.off);
    });
  });

  test('a press while the switch is off sends nothing and says why', () {
    _scenario((async, f) {
      f.controller.press(1, 'robot', 'x', 1);
      async.flushMicrotasks();
      expect(f.commands, isEmpty);
      expect(f.said.single!.kind, HydraErrorKind.deadManBlocked);
      expect(f.said.single!.params['block'], DeadManBlock.off.name);
      expect(f.controller.held, isEmpty);
    });
  });

  test('a press and a release send start, heartbeats and stop, and the control is not held afterwards', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.controller.press(1, 'robot', 'x', -1);
      async.flushMicrotasks();
      expect(f.controller.held, {1});
      async.elapse(const Duration(milliseconds: 500));
      expect(f.count(RobotCommandContract.jogHeartbeat), greaterThanOrEqualTo(4));
      f.controller.release(1);
      async.flushMicrotasks();
      expect(f.controller.held, isEmpty);
      expect(f.count(RobotCommandContract.jogStop), 1);
      expect(f.said.whereType<HydraError>(), isEmpty);
    });
  });

  test('the direction is the sign of the speed', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.controller.setVelocity(33);
      expect(f.controller.velocity, 33);
      f.controller.setVelocity(5000);
      expect(f.controller.velocity, 100);
      f.controller.setVelocity(-4);
      expect(f.controller.velocity, 1);
    });
  });

  test('a robot that is running a trajectory, a second press and a lost connection are refused', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.robotPlaying = true;
      expect(f.controller.blockOf(1), DeadManBlock.moving);
      f.robotPlaying = false;
      f.connected = false;
      expect(f.controller.blockOf(1), DeadManBlock.notConnected);
      f.connected = true;
      f.controller.press(1, 'robot', 'x', 1);
      async.flushMicrotasks();
      expect(f.controller.blockOf(1), DeadManBlock.alreadyRunning);
      f.controller.release(1);
      async.flushMicrotasks();
    });
  });

  test('a server that does not know the commands is remembered and nothing keeps running', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.startError = HydraApiException('x', statusCode: 400, serverMessage: 'unknown command: jogStart');
      f.controller.press(1, 'robot', 'x', 1);
      async.flushMicrotasks();
      expect(f.controller.serverSupports, isFalse);
      expect(f.controller.held, isEmpty);
      expect(f.controller.blockOf(1), DeadManBlock.notSupported);
      expect(f.said.last!.kind, HydraErrorKind.txError);
      async.elapse(const Duration(seconds: 1));
      expect(f.count(RobotCommandContract.jogHeartbeat), 0);
    });
  });

  test('interrupting stops the axis and clears the held controls', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.controller.press(1, 'robot', 'x', 1);
      async.elapse(const Duration(milliseconds: 250));
      f.controller.interrupt();
      async.flushMicrotasks();
      expect(f.controller.held, isEmpty);
      expect(f.count(RobotCommandContract.jogStop), 1);
      expect(f.said.whereType<HydraError>(), isEmpty, reason: 'an interruption by the app is not announced as a failure');
      f.controller.interrupt(); // nothing to stop: no second stop
      async.flushMicrotasks();
      expect(f.count(RobotCommandContract.jogStop), 1);
    });
  });

  test('a link that drops while the control is held stops the axis and says so', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.controller.press(1, 'robot', 'x', 1);
      async.elapse(const Duration(milliseconds: 250));
      f.heartbeatError = StateError('down');
      async.elapse(const Duration(milliseconds: 400));
      expect(f.controller.held, isEmpty);
      expect(f.count(RobotCommandContract.jogStop), 1);
      expect(f.said.last!.kind, HydraErrorKind.deadManEnded);
      expect(f.said.last!.params['reason'], DeadManEnd.linkLost.name);
    });
  });

  test('a slow link blocks the jog, and the block can be switched off', () {
    _scenario((async, f) {
      f.controller.enabled = true;
      f.controller.link.record(RobotCommandContract.linkBlockRttMs);
      expect(f.controller.blockOf(1), DeadManBlock.badLink);
      f.controller.blockOnBadLink = false;
      expect(f.controller.blockOf(1), DeadManBlock.none);
    });
  });

  test('the probe measures the link while it is active and counts a silence as a failure', () {
    _scenario((async, f) {
      var active = true;
      f.controller.ensureProbe(() => active);
      async.flushMicrotasks();
      expect(f.controller.linkLevel, LinkLevel.good);
      expect(f.controller.linkRttMs, 20);
      f.pingMs = 700;
      async.elapse(const Duration(milliseconds: RobotCommandContract.linkProbeIntervalMs));
      expect(f.controller.linkLevel, LinkLevel.bad);
      f.pingFails = true;
      async.elapse(const Duration(milliseconds: RobotCommandContract.linkProbeIntervalMs * 2));
      expect(f.controller.linkLevel, LinkLevel.lost);
      active = false;
      async.elapse(const Duration(milliseconds: RobotCommandContract.linkProbeIntervalMs));
      expect(f.controller.linkLevel, LinkLevel.unknown, reason: 'the meter forgets everything when the connection ends');
    });
  });

  test('without the indicator and without the jog nothing is probed', () {
    _scenario((async, f) {
      f.controller.indicator = false;
      f.controller.ensureProbe(() => true);
      async.elapse(const Duration(seconds: 10));
      expect(f.controller.linkRttMs, isNull);
    });
  });
}
