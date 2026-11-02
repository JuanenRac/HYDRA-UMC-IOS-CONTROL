// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/dead_man_jog_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The continuous jog held by a dead-man: the rules (when it refuses to start, how the speed is bounded, the watchdog) and the
// runner against a fake server and a fake clock. No robot is involved. It checks the order of the three commands, the rhythm of
// the heartbeat and, above all, that the axis is stopped in every way a session can end.
// =============================================================================

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/network/dead_man_jog_runner.dart';
import 'package:hydra_umc_control/network/hydra_api_client.dart';
import 'package:hydra_umc_control/util/dead_man_jog.dart';

DeadManSituation _situation({
  bool switchedOn = true,
  bool connected = true,
  bool robotOnline = true,
  bool robotEnabled = true,
  bool robotPlaying = false,
  bool stopInProgress = false,
  bool needsArming = false,
  String? role = 'operator',
  bool linkBlocks = false,
  bool alreadyRunning = false,
  bool serverSupports = true,
}) =>
    DeadManSituation(
      switchedOn: switchedOn,
      connected: connected,
      robotOnline: robotOnline,
      robotEnabled: robotEnabled,
      robotPlaying: robotPlaying,
      stopInProgress: stopInProgress,
      needsArming: needsArming,
      role: role,
      linkBlocks: linkBlocks,
      alreadyRunning: alreadyRunning,
      serverSupports: serverSupports,
    );

class _FakeServer {
  final List<(String, Map<String, dynamic>)> log = [];
  Object? failHeartbeats;
  bool hangHeartbeats = false;
  int stopFailures = 0;
  Object? startFailure;

  Future<Map<String, dynamic>> post(dynamic robotId, Map<String, dynamic> payload, {required bool urgent, String? ifMatch}) async {
    final command = payload['command'] as String;
    log.add((command, Map<String, dynamic>.from(payload['params'] as Map)));
    switch (command) {
      case RobotCommandContract.jogStart:
        if (startFailure != null) throw startFailure!;
      case RobotCommandContract.jogHeartbeat:
        if (hangHeartbeats) await Completer<void>().future;
        if (failHeartbeats != null) throw failHeartbeats!;
      case RobotCommandContract.jogStop:
        if (stopFailures > 0) {
          stopFailures--;
          throw StateError('no answer');
        }
    }
    return {'ok': true};
  }

  int count(String command) => log.where((e) => e.$1 == command).length;
}

class _Ended {
  final DeadManEnd reason;
  final bool confirmed;
  _Ended(this.reason, this.confirmed);
}

void main() {
  group('the rules', () {
    test('the contract starts the jog off and bounds the speed', () {
      expect(RobotCommandContract.deadManEnabledByDefault, isFalse);
      expect(clampDeadManVelocity(5000), 100.0);
      expect(clampDeadManVelocity(-5000), -100.0);
      expect(clampDeadManVelocity(0), 1.0);
      expect(clampDeadManVelocity(double.nan), 1.0);
      expect(clampDeadManVelocity(-0.2), -1.0);
      expect(clampDeadManVelocity(20), 20.0);
    });

    test('the server timeout is longer than the heartbeat', () {
      expect(RobotCommandContract.deadManServerTimeoutMs, greaterThan(RobotCommandContract.deadManHeartbeatMs));
      expect(() => DeadManSettings(heartbeatMs: 300, serverTimeoutMs: 300), throwsA(isA<AssertionError>()));
    });

    test('the first reason not to start wins, in the order a person can fix them', () {
      expect(deadManBlockOf(_situation()), DeadManBlock.none);
      expect(deadManBlockOf(_situation(switchedOn: false, connected: false)), DeadManBlock.off);
      expect(deadManBlockOf(_situation(connected: false)), DeadManBlock.notConnected);
      expect(deadManBlockOf(_situation(serverSupports: false)), DeadManBlock.notSupported);
      expect(deadManBlockOf(_situation(role: 'viewer')), DeadManBlock.role);
      expect(deadManBlockOf(_situation(role: null)), DeadManBlock.none);
      expect(deadManBlockOf(_situation(robotOnline: false)), DeadManBlock.offline);
      expect(deadManBlockOf(_situation(robotEnabled: false)), DeadManBlock.safeMode);
      expect(deadManBlockOf(_situation(stopInProgress: true, robotPlaying: true)), DeadManBlock.stopPending);
      expect(deadManBlockOf(_situation(robotPlaying: true)), DeadManBlock.moving);
      expect(deadManBlockOf(_situation(needsArming: true)), DeadManBlock.notArmed);
      expect(deadManBlockOf(_situation(alreadyRunning: true)), DeadManBlock.alreadyRunning);
      expect(deadManBlockOf(_situation(linkBlocks: true)), DeadManBlock.badLink);
    });

    test('the watchdog gives the link up on missed heartbeats, on silence and on a hold that is too long', () {
      var now = 0;
      final dog = DeadManWatchdog(const DeadManSettings(), () => now);
      expect(dog.verdict(), isNull);
      dog.missed();
      expect(dog.verdict(), isNull);
      dog.acked();
      expect(dog.missedInARow, 0);
      dog.missed();
      dog.missed();
      expect(dog.verdict(), DeadManEnd.linkLost);

      final silent = DeadManWatchdog(const DeadManSettings(), () => now);
      now += RobotCommandContract.deadManServerTimeoutMs + 1;
      expect(silent.verdict(), DeadManEnd.linkLost);

      final long = DeadManWatchdog(const DeadManSettings(maxHoldMs: 1000), () => now);
      for (var i = 0; i < 20; i++) {
        now += 90;
        long.acked();
      }
      expect(long.verdict(), DeadManEnd.tooLong);
    });
  });

  group('the runner', () {
    // Runs [body] with a fake clock; [elapse] moves it and lets every pending future run.
    void scenario(void Function(FakeAsync async, _FakeServer server, List<_Ended> ended, DeadManJogRunner Function({DeadManSettings settings, bool Function()? linkAllows, List<int>? samples}) make) body) {
      fakeAsync((async) {
        final server = _FakeServer();
        final ended = <_Ended>[];
        DeadManJogRunner make({DeadManSettings settings = const DeadManSettings(), bool Function()? linkAllows, List<int>? samples}) => DeadManJogRunner(
              poster: server.post,
              settings: settings,
              clock: () => async.elapsed.inMilliseconds,
              linkAllows: linkAllows,
              onRoundTrip: samples?.add,
              onEnded: (_, reason, confirmed) => ended.add(_Ended(reason, confirmed)),
            );
        body(async, server, ended, make);
      });
    }

    test('a start, a heartbeat every 100 ms and a stop on release', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        expect(runner.isRunning(1), isTrue);
        expect(server.log.first.$1, RobotCommandContract.jogStart);
        async.elapse(const Duration(seconds: 1));
        expect(server.count(RobotCommandContract.jogHeartbeat), inInclusiveRange(9, 11));
        runner.release(1);
        async.flushMicrotasks();
        expect(server.count(RobotCommandContract.jogStop), 1);
        expect(server.log.last.$1, RobotCommandContract.jogStop);
        expect(ended.single.reason, DeadManEnd.released);
        expect(ended.single.confirmed, isTrue);
        expect(runner.isRunning(1), isFalse);
        final heartbeats = server.count(RobotCommandContract.jogHeartbeat);
        async.elapse(const Duration(seconds: 1));
        expect(server.count(RobotCommandContract.jogHeartbeat), heartbeats, reason: 'no heartbeat after the release');
      });
    });

    test('the session id travels in every command and the speed is bounded', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(2, 'robot', 'z', 5000));
        async.elapse(const Duration(milliseconds: 250));
        runner.release(2);
        async.flushMicrotasks();
        expect(server.log.map((e) => e.$2['sessionId']).toSet(), hasLength(1));
        expect(server.log.first.$2['velocity'], 100.0);
        expect(server.log.first.$2['heartbeatMs'], 100);
        expect(server.log.first.$2['timeoutMs'], 300);
        final sequences = [for (final e in server.log) if (e.$1 == RobotCommandContract.jogHeartbeat) e.$2['sequence'] as int];
        expect(sequences, [...sequences]..sort());
        expect(sequences.toSet(), hasLength(sequences.length));
      });
    });

    test('failed heartbeats stop the axis by themselves', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.failHeartbeats = StateError('link down');
        async.elapse(const Duration(milliseconds: 400));
        expect(ended.single.reason, DeadManEnd.linkLost);
        expect(server.count(RobotCommandContract.jogStop), 1);
        expect(runner.isRunning(1), isFalse);
      });
    });

    test('a heartbeat that never answers stops the axis', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.hangHeartbeats = true;
        async.elapse(const Duration(milliseconds: 700));
        expect(ended.single.reason, DeadManEnd.linkLost);
        expect(server.count(RobotCommandContract.jogStop), 1);
      });
    });

    test('a refusal of the server ends the session at once', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.failHeartbeats = HydraApiException('reserved', statusCode: 409);
        async.elapse(const Duration(milliseconds: 150));
        expect(ended.single.reason, DeadManEnd.serverRefused);
        expect(server.count(RobotCommandContract.jogStop), 1);
      });
    });

    test('a rate limit or a timeout of the server counts as a missed heartbeat, not as a refusal', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.failHeartbeats = HydraApiException('slow down', statusCode: 429);
        async.elapse(const Duration(milliseconds: 400));
        expect(ended.single.reason, DeadManEnd.linkLost);
      });
    });

    test('a bad link ends the session', () {
      scenario((async, server, ended, make) {
        var allowed = true;
        final runner = make(linkAllows: () => allowed);
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.elapse(const Duration(milliseconds: 300));
        allowed = false;
        async.elapse(const Duration(milliseconds: 200));
        expect(ended.single.reason, DeadManEnd.badLink);
        expect(server.count(RobotCommandContract.jogStop), 1);
      });
    });

    test('a hold past the limit ends', () {
      scenario((async, server, ended, make) {
        final runner = make(settings: const DeadManSettings(maxHoldMs: 1000));
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.elapse(const Duration(milliseconds: 1500));
        expect(ended.single.reason, DeadManEnd.tooLong);
        expect(server.count(RobotCommandContract.jogStop), 1);
      });
    });

    test('interrupting stops every axis', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        unawaited(runner.start(2, 'robot', 'y', 20));
        async.elapse(const Duration(milliseconds: 250));
        runner.interrupt();
        async.flushMicrotasks();
        expect(server.count(RobotCommandContract.jogStop), 2);
        expect(ended.map((e) => e.reason), [DeadManEnd.interrupted, DeadManEnd.interrupted]);
        expect(runner.anyRunning, isFalse);
      });
    });

    test('a stop that does not arrive is tried again, and reported as not confirmed if it never does', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.stopFailures = 2;
        runner.release(1);
        async.elapse(const Duration(seconds: 1));
        expect(server.count(RobotCommandContract.jogStop), 3);
        expect(ended.single.confirmed, isTrue);

        server.log.clear();
        ended.clear();
        unawaited(runner.start(3, 'robot', 'x', 20));
        async.flushMicrotasks();
        server.stopFailures = 99;
        runner.release(3);
        async.elapse(const Duration(seconds: 1));
        expect(server.count(RobotCommandContract.jogStop), 3);
        expect(ended.single.confirmed, isFalse);
      });
    });

    test('a start the server refuses leaves nothing running', () {
      scenario((async, server, ended, make) {
        final runner = make();
        server.startFailure = HydraApiException('unknown command', statusCode: 400, serverMessage: 'unknown command');
        Object? failure;
        runner.start(1, 'robot', 'x', 20).catchError((Object e) => failure = e);
        async.flushMicrotasks();
        expect(failure, isA<HydraApiException>());
        expect(runner.isRunning(1), isFalse);
        async.elapse(const Duration(milliseconds: 500));
        expect(server.count(RobotCommandContract.jogHeartbeat), 0);
        expect(server.count(RobotCommandContract.jogStop), 0);
      });
    });

    test('a release while the start is still on the wire stops the axis', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        runner.release(1); // the finger left before the answer of the start
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(server.count(RobotCommandContract.jogStop), 1);
        expect(server.count(RobotCommandContract.jogHeartbeat), 0);
      });
    });

    test('the round trip of each heartbeat is reported', () {
      scenario((async, server, ended, make) {
        final samples = <int>[];
        final runner = make(samples: samples);
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.elapse(const Duration(milliseconds: 350));
        expect(samples.length, greaterThanOrEqualTo(3));
        expect(samples.every((s) => s >= 0), isTrue);
        runner.release(1);
        async.flushMicrotasks();
      });
    });

    test('a second start of the same robot does nothing', () {
      scenario((async, server, ended, make) {
        final runner = make();
        unawaited(runner.start(1, 'robot', 'x', 20));
        async.flushMicrotasks();
        unawaited(runner.start(1, 'robot', 'y', 20));
        async.flushMicrotasks();
        expect(server.count(RobotCommandContract.jogStart), 1);
        runner.release(1);
        async.flushMicrotasks();
      });
    });
  });
}
