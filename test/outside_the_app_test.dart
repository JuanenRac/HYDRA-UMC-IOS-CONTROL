// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/outside_the_app_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The logic of what the app shows outside its own screens, on the Dart VM (no iPhone, no Xcode):
//   - the link health, the ecosystem reading and the connection report;
//   - the rationed notifications of a job, the Live Activity and the Apple Watch planners;
//   - the surfaces with fake bridges: everything starts off, a refused permission stays off, a stale watch stop is dropped;
//   - the contract: what reaches out of the app starts off, and the generated constants follow the JSON.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/models/ecosystem.dart';
import 'package:hydra_umc_control/models/ios_feature_contract.dart';
import 'package:hydra_umc_control/models/robot_command_contract.dart';
import 'package:hydra_umc_control/network/native_bridges.dart';
import 'package:hydra_umc_control/state/external_surfaces.dart';
import 'package:hydra_umc_control/util/connection_diagnostics.dart';
import 'package:hydra_umc_control/util/job_alerts.dart';
import 'package:hydra_umc_control/util/link_health.dart';
import 'package:hydra_umc_control/util/live_activity_model.dart';

RobotSnapshot _robot({
  String id = '1',
  String name = 'Parol6',
  bool online = true,
  bool enabled = true,
  bool playing = false,
  bool paused = false,
  bool finished = false,
  int step = -1,
  int total = 10,
}) =>
    RobotSnapshot(id: id, name: name, online: online, enabled: enabled, playing: playing, paused: paused, finished: finished, activeStep: step, totalSteps: total);

class _FakeAlerts implements AlertsBridge {
  bool grant = true;
  int asked = 0;
  final List<Map<String, String>> shown = [];
  @override
  Future<bool> requestPermission() async {
    asked++;
    return grant;
  }

  @override
  Future<void> show({required String id, required String title, required String body}) async => shown.add({'id': id, 'title': title, 'body': body});
}

class _FakeLive implements LiveActivityBridge {
  bool available = true;
  final List<String> calls = [];
  Map<String, Object>? last;
  int? dismiss;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> start(Map<String, Object> content, {bool pushToken = false}) async {
    calls.add('start');
    last = content;
    return true;
  }

  @override
  void listenForPushToken(void Function(String token) onToken) {}

  @override
  Future<void> update(Map<String, Object> content) async {
    calls.add('update');
    last = content;
  }

  @override
  Future<void> end(Map<String, Object> content, {int dismissAfterSeconds = 0}) async {
    calls.add('end');
    last = content;
    dismiss = dismissAfterSeconds;
  }
}

class _FakeWatch implements WatchBridge {
  final List<Map<String, Object>> sent = [];
  bool Function(DateTime)? onStop;
  @override
  Future<bool> isReachable() async => true;
  @override
  Future<void> sendStatus(Map<String, Object> status) async => sent.add(status);
  @override
  void listenForStop(bool Function(DateTime requestedAt) onStop) => this.onStop = onStop;
  @override
  Future<bool> sendAlert(Map<String, Object> alert) async => true;
  @override
  void listenForRelays({
    required Future<void> Function(Map<dynamic, dynamic> heartbeat) onPresence,
    required Future<Map<String, Object?>?> Function(Map<dynamic, dynamic> confirm) onVoiceConfirm,
  }) {}
}

void main() {
  group('link health', () {
    test('grades by the slowest recent answer, and a link nobody measured does not block', () {
      var now = DateTime(2000);
      final link = LinkHealth(clock: () => now);
      expect(link.level, LinkLevel.unknown);
      expect(link.blocksJog, isFalse);
      link.record(20);
      link.record(40);
      expect(link.level, LinkLevel.good);
      link.record(RobotCommandContract.linkPoorRttMs - 1);
      expect(link.level, LinkLevel.poor);
      link.record(RobotCommandContract.linkBlockRttMs);
      expect(link.level, LinkLevel.bad);
      expect(link.blocksJog, isTrue);
      expect(link.worstMs, RobotCommandContract.linkBlockRttMs);
      expect(link.lastMs, RobotCommandContract.linkBlockRttMs);
    });

    test('two misses or a long silence mean lost, and an answer after a miss recovers', () {
      var now = DateTime(2000);
      final link = LinkHealth(clock: () => now);
      link.record(30);
      link.recordFailure();
      expect(link.level, LinkLevel.good);
      link.recordFailure();
      expect(link.level, LinkLevel.lost);
      link.record(30);
      expect(link.level, LinkLevel.good);
      now = now.add(Duration(milliseconds: RobotCommandContract.linkLostAfterMs + 1));
      expect(link.level, LinkLevel.lost);
      link.reset();
      expect(link.level, LinkLevel.unknown);
    });

    test('only the last window of samples counts', () {
      final link = LinkHealth(limits: const LinkLimits(window: 2));
      link.record(900);
      link.record(10);
      link.record(10);
      expect(link.worstMs, 10);
    });
  });

  group('ecosystem', () {
    test('reads the projects, keeps "never probed" apart from "down" and skips damaged entries', () {
      final status = EcosystemStatus.fromJson(jsonDecode('''
        {"available": true, "projects": [
          {"name": "HYDRA-UMC-SERVER", "family": "Core", "maturity": "established", "version": "0.9.0", "servicePort": 3000, "live": true},
          {"name": "HYDRA-UMC-DSI", "family": "Core", "maturity": "functional", "servicePort": 18080, "live": false},
          {"name": "HYDRA-UMC-SDK", "family": "Libraries", "servicePort": null, "live": null},
          {"role": "no name"}, 42, null,
          {"name": "Odd", "servicePort": 99999, "live": "yes"}
        ]}'''));
      expect(status.available, isTrue);
      expect(status.projects.map((p) => p.name), ['HYDRA-UMC-SERVER', 'HYDRA-UMC-DSI', 'HYDRA-UMC-SDK', 'Odd']);
      expect(status.projects[0].live, isTrue);
      expect(status.projects[1].live, isFalse);
      expect(status.projects[2].live, isNull);
      expect(status.projects[2].servicePort, isNull);
      expect(status.projects[3].servicePort, isNull, reason: 'a port out of range is dropped');
      expect(status.projects[3].live, isNull, reason: 'only a real boolean is a probe result');
      expect(status.byFamily.keys, ['Core', 'Libraries', '—']);
    });

    test('anything that is not an object reads as unavailable', () {
      expect(EcosystemStatus.fromJson('no').available, isFalse);
      expect(EcosystemStatus.fromJson(<String, dynamic>{'available': false}).projects, isEmpty);
    });
  });

  group('connection diagnostics', () {
    test('the report carries the facts and nothing secret', () {
      final fingerprint = 'ab' * 32;
      final diagnostics = ConnectionDiagnostics(
        scheme: 'https',
        host: '192.168.0.180',
        port: 3000,
        trust: ConnectionDiagnostics.trustFor(scheme: 'https', pinnedFingerprint: fingerprint, customCaPem: ''),
        pinnedFingerprint: fingerprint,
        remoteApiVersion: 2,
        serverAppVersion: '0.9.0',
        clientVersion: '0.3.0',
        latenciesMs: [12, null, 30],
        level: LinkLevel.good,
        websocket: 'connected',
        role: 'operator',
      );
      final text = diagnostics.report();
      expect(text, contains('address: https://192.168.0.180:3000'));
      expect(text, contains('trust: pinnedFingerprint'));
      expect(text, contains('pinned fingerprint (SHA-256): $fingerprint'));
      expect(text, contains('server remote API version: 2'));
      expect(text, contains('probes: 3 sent, 1 without answer'));
      expect(text, contains('latency: min 12 ms, average 21 ms, max 30 ms'));
      expect(text, contains('probe 2: none'));
      expect(text, contains('link level: good'));
      expect(text.toLowerCase(), isNot(contains('token')));
      expect(text.toLowerCase(), isNot(contains('password')));
      expect(diagnostics.report(maxLines: 3).split('\n'), hasLength(3));
    });

    test('the trust follows the scheme, then the fingerprint, then the own authority', () {
      TrustMode trust(String scheme, String fp, String pem) =>
          ConnectionDiagnostics.trustFor(scheme: scheme, pinnedFingerprint: fp, customCaPem: pem);
      expect(trust('http', 'ab', 'pem'), TrustMode.plainHttp);
      expect(trust('https', 'ab', 'pem'), TrustMode.pinnedFingerprint);
      expect(trust('https', '', 'pem'), TrustMode.customAuthority);
      expect(trust('https', ' ', ''), TrustMode.systemCertificates);
    });

    test('with no answer the figures are unknown, not zero', () {
      const diagnostics = ConnectionDiagnostics(scheme: 'http', host: 'h', port: 1, trust: TrustMode.plainHttp, clientVersion: '1', latenciesMs: [null, null]);
      expect(diagnostics.minMs, isNull);
      expect(diagnostics.averageMs, isNull);
      expect(diagnostics.lost, 2);
      expect(diagnostics.report(), contains('latency: min none, average none, max none'));
    });
  });

  group('notifications of a job', () {
    final t0 = DateTime(2000, 1, 1, 12);

    test('the first reading is only the baseline, so a finished job found on opening does not notify', () {
      final detector = JobAlertDetector();
      expect(detector.update([_robot(finished: true)], t0), isEmpty);
    });

    test('a job that finishes, a robot that goes offline and one in safe mode each notify once', () {
      final detector = JobAlertDetector();
      detector.update([_robot(playing: true, step: 3), _robot(id: '2', name: 'B'), _robot(id: '3', name: 'C')], t0);
      final events = detector.update([
        _robot(finished: true),
        _robot(id: '2', name: 'B', online: false),
        _robot(id: '3', name: 'C', enabled: false),
      ], t0.add(const Duration(seconds: 5)));
      expect(events.map((e) => e.kind), [AlertKind.jobFinished, AlertKind.robotOffline, AlertKind.robotSafeMode]);
      expect(events.first.robotName, 'Parol6');
      // the same readings again change nothing
      expect(detector.update([_robot(finished: true), _robot(id: '2', name: 'B', online: false), _robot(id: '3', name: 'C', enabled: false)], t0.add(const Duration(seconds: 6))), isEmpty);
    });

    test('a job that was stopped by the person is not a finished job', () {
      final detector = JobAlertDetector();
      detector.update([_robot(playing: true, step: 2)], t0);
      expect(detector.update([_robot()], t0.add(const Duration(seconds: 3))), isEmpty);
    });

    test('the same alert is not repeated inside the dedupe window, and is allowed after it', () {
      final detector = JobAlertDetector();
      var at = t0;
      void flap() {
        detector.update([_robot(online: true)], at);
        at = at.add(const Duration(seconds: 3));
      }

      flap();
      expect(detector.update([_robot(online: false)], at), hasLength(1));
      at = at.add(const Duration(seconds: 3));
      flap();
      expect(detector.update([_robot(online: false)], at), isEmpty, reason: 'inside the window');
      at = at.add(const Duration(milliseconds: JobAlertsContract.dedupeWindowMs));
      flap();
      expect(detector.update([_robot(online: false)], at), hasLength(1));
    });

    test('no more than the limit per minute', () {
      final detector = JobAlertDetector(dedupeWindow: Duration.zero, minGap: Duration.zero, maxPerMinute: 2);
      var at = t0;
      var count = 0;
      for (var i = 0; i < 6; i++) {
        detector.update([_robot(id: 'r$i')], at);
        count += detector.update([_robot(id: 'r$i', online: false)], at).length;
        at = at.add(const Duration(seconds: 1));
      }
      expect(count, 2);
    });

    test('a lost connection notifies once after the wait, never before the first connection, and arms again', () {
      final detector = JobAlertDetector();
      expect(detector.linkUpdate(connected: false, now: t0.add(const Duration(minutes: 1))), isEmpty, reason: 'never up');
      expect(detector.linkUpdate(connected: true, now: t0), isEmpty);
      expect(detector.linkUpdate(connected: false, now: t0.add(const Duration(seconds: 1))), isEmpty);
      final later = t0.add(Duration(milliseconds: 1000 + JobAlertsContract.connectionLostAfterMs));
      expect(detector.linkUpdate(connected: false, now: later).single.kind, AlertKind.connectionLost);
      expect(detector.linkUpdate(connected: false, now: later.add(const Duration(minutes: 5))), isEmpty);
      expect(detector.linkUpdate(connected: true, now: later.add(const Duration(minutes: 6))), isEmpty);
      expect(detector.linkUpdate(connected: false, now: later.add(const Duration(minutes: 7))), isEmpty);
      expect(detector.linkUpdate(connected: false, now: later.add(const Duration(minutes: 8))), hasLength(1));
    });
  });

  group('Live Activity and Apple Watch planners', () {
    final t0 = DateTime(2000, 1, 1, 12);

    test('the content counts the step from 1, never beyond the total, and cuts a long name', () {
      final c = SurfaceContent.of(_robot(playing: true, step: 0, total: 10));
      expect((c.status, c.step, c.total), (SurfaceStatus.running, 1, 10));
      expect(SurfaceContent.of(_robot(playing: true, step: 99, total: 10)).step, 10);
      expect(SurfaceContent.of(_robot(playing: true, paused: true, step: 2)).status, SurfaceStatus.paused);
      expect(SurfaceContent.of(_robot(finished: true)).step, 10);
      expect(SurfaceContent.of(_robot(online: false)).status, SurfaceStatus.offline);
      expect(SurfaceContent.of(_robot(enabled: false)).status, SurfaceStatus.safeMode);
      final longName = SurfaceContent.shortName('X' * 100);
      expect(longName.runes.length, LiveActivityContract.nameMax);
      expect(longName, endsWith('…'));
      expect(c.toMap(), {'robotName': 'Parol6', 'status': 'running', 'step': 1, 'total': 10});
    });

    test('it shows the robot that plays, else one whose job just finished, else nothing', () {
      final idle = _robot(id: '1');
      final playing = _robot(id: '2', name: 'B', playing: true, step: 1);
      final done = _robot(id: '3', name: 'C', finished: true);
      expect(SurfaceContent.choose([idle, done, playing])!.robotName, 'B');
      expect(SurfaceContent.choose([idle, done])!.robotName, 'C');
      expect(SurfaceContent.choose([idle]), isNull);
    });

    test('it starts when a job plays, follows the steps no faster than the gap, and ends with the result kept on the screen', () {
      final planner = LiveActivityPlanner();
      expect(planner.next(null, t0).action, ActivityAction.none);
      expect(planner.next(SurfaceContent.of(_robot(finished: true)), t0).action, ActivityAction.none, reason: 'a finished job does not start one');
      expect(planner.next(SurfaceContent.of(_robot(playing: true, step: 0)), t0).action, ActivityAction.start);
      expect(planner.active, isTrue);
      expect(planner.next(SurfaceContent.of(_robot(playing: true, step: 0)), t0).action, ActivityAction.none, reason: 'same content');
      expect(planner.next(SurfaceContent.of(_robot(playing: true, step: 1)), t0.add(const Duration(milliseconds: 500))).action, ActivityAction.none, reason: 'too soon');
      expect(planner.next(SurfaceContent.of(_robot(playing: true, step: 1)), t0.add(const Duration(seconds: 3))).action, ActivityAction.update);
      final pause = planner.next(SurfaceContent.of(_robot(playing: true, paused: true, step: 1)), t0.add(const Duration(seconds: 3, milliseconds: 100)));
      expect(pause.action, ActivityAction.update, reason: 'a pause goes out at once');
      final end = planner.next(SurfaceContent.of(_robot(finished: true)), t0.add(const Duration(seconds: 9)));
      expect(end.action, ActivityAction.end);
      expect(end.dismissAfterSeconds, LiveActivityContract.endAfterFinishedSeconds);
      expect(planner.active, isFalse);
    });

    test('a robot that goes offline or a lost session ends it at once', () {
      final planner = LiveActivityPlanner();
      planner.next(SurfaceContent.of(_robot(playing: true, step: 0)), t0);
      final offline = planner.next(SurfaceContent.of(_robot(playing: true, online: false)), t0.add(const Duration(seconds: 5)));
      expect((offline.action, offline.dismissAfterSeconds), (ActivityAction.end, 0));
      planner.next(SurfaceContent.of(_robot(playing: true, step: 0)), t0.add(const Duration(seconds: 6)));
      expect(planner.next(null, t0.add(const Duration(seconds: 7))).action, ActivityAction.end);
      planner.next(SurfaceContent.of(_robot(playing: true, step: 0)), t0.add(const Duration(seconds: 8)));
      expect(planner.stop().action, ActivityAction.end);
      expect(planner.stop().action, ActivityAction.none);
    });

    test('the watch gets a status when it changes, the step counter no faster than the gap, and nothing when nothing changed', () {
      final planner = WatchStatusPlanner();
      final c1 = SurfaceContent.of(_robot(playing: true, step: 0));
      final c2 = SurfaceContent.of(_robot(playing: true, step: 1));
      expect(planner.next(content: c1, connected: true, now: t0), isNotNull);
      expect(planner.next(content: c1, connected: true, now: t0.add(const Duration(seconds: 5))), isNull);
      expect(planner.next(content: c2, connected: true, now: t0.add(const Duration(milliseconds: 200))), isNull, reason: 'step too soon');
      expect(planner.next(content: c2, connected: true, now: t0.add(const Duration(seconds: 2)))!['step'], 2);
      expect(planner.next(content: null, connected: false, now: t0.add(const Duration(seconds: 2, milliseconds: 10)))!['connected'], false);
    });

    test('a stop asked for on the watch is carried out while fresh and dropped when it is old or from the future', () {
      expect(watchStopIsFresh(t0, t0.add(const Duration(seconds: 1))), isTrue);
      expect(watchStopIsFresh(t0, t0.add(Duration(milliseconds: WatchCompanionContract.stopMaxAgeMs + 1))), isFalse);
      expect(watchStopIsFresh(t0.add(const Duration(minutes: 1)), t0), isFalse);
    });
  });

  group('the surfaces with fake bridges', () {
    final t0 = DateTime(2000, 1, 1, 12);

    test('everything starts off and nothing reaches out of the app', () async {
      final alerts = _FakeAlerts();
      final live = _FakeLive();
      final watch = _FakeWatch();
      final surfaces = ExternalSurfaces(alerts: alerts, liveActivity: live, watch: watch, clock: () => t0);
      addTearDown(surfaces.dispose);
      expect((surfaces.jobAlertsEnabled, surfaces.liveActivityEnabled, surfaces.watchEnabled), (false, false, false));
      await surfaces.onState([_robot(playing: true, step: 1)], connected: true);
      expect(live.calls, isEmpty);
      expect(watch.sent, isEmpty);
      expect(alerts.shown, isEmpty);
      expect(alerts.asked, 0);
    });

    test('turning the notifications on asks the system; a refusal leaves them off', () async {
      final alerts = _FakeAlerts()..grant = false;
      final surfaces = ExternalSurfaces(alerts: alerts, liveActivity: _FakeLive(), watch: _FakeWatch(), clock: () => t0);
      addTearDown(surfaces.dispose);
      expect(await surfaces.setJobAlerts(true), isFalse);
      expect(surfaces.jobAlertsEnabled, isFalse);
      alerts.grant = true;
      expect(await surfaces.setJobAlerts(true), isTrue);
      expect(surfaces.jobAlertsEnabled, isTrue);
      expect(alerts.asked, 2);
      expect(await surfaces.setJobAlerts(false), isFalse);
      expect(surfaces.jobAlertsEnabled, isFalse);
    });

    test('with them on, a finished job comes out as an event for the screen to put in words', () async {
      var now = t0;
      final surfaces = ExternalSurfaces(alerts: _FakeAlerts(), liveActivity: _FakeLive(), watch: _FakeWatch(), clock: () => now);
      addTearDown(surfaces.dispose);
      await surfaces.setJobAlerts(true);
      final events = <AlertEvent>[];
      final sub = surfaces.alerts.listen(events.add);
      addTearDown(sub.cancel);
      await surfaces.onState([_robot(playing: true, step: 3)], connected: true);
      now = now.add(const Duration(seconds: 4));
      await surfaces.onState([_robot(finished: true)], connected: true);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.kind), [AlertKind.jobFinished]);
      await surfaces.showNotification(id: 'a', title: 'T', body: 'B');
    });

    test('the Live Activity starts, updates and ends through the bridge, and a refusal of the system is remembered', () async {
      var now = t0;
      final live = _FakeLive();
      final surfaces = ExternalSurfaces(alerts: _FakeAlerts(), liveActivity: live, watch: _FakeWatch(), clock: () => now);
      addTearDown(surfaces.dispose);
      await surfaces.setLiveActivity(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      now = now.add(const Duration(seconds: 3));
      await surfaces.onState([_robot(playing: true, step: 4)], connected: true);
      now = now.add(const Duration(seconds: 3));
      await surfaces.onState([_robot(finished: true)], connected: true);
      expect(live.calls, ['start', 'update', 'end']);
      expect(live.dismiss, LiveActivityContract.endAfterFinishedSeconds);
      expect(live.last!['staleAfterSeconds'], LiveActivityContract.staleAfterSeconds);

      live.calls.clear();
      live.available = false;
      now = now.add(const Duration(seconds: 3));
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      expect(live.calls, isEmpty);
      expect(surfaces.liveActivityRefusedBySystem, isTrue);
      live.available = true;
      now = now.add(const Duration(seconds: 3));
      await surfaces.onState([_robot(playing: true, step: 1)], connected: true);
      expect(live.calls, ['start'], reason: 'it tries again when the system allows it');
    });

    test('turning the Live Activity off or ending the session takes it off the screen at once', () async {
      final live = _FakeLive();
      final surfaces = ExternalSurfaces(alerts: _FakeAlerts(), liveActivity: live, watch: _FakeWatch(), clock: () => t0);
      addTearDown(surfaces.dispose);
      await surfaces.setLiveActivity(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      await surfaces.setLiveActivity(false);
      expect(live.calls, ['start', 'end']);
      await surfaces.setLiveActivity(true);
      await surfaces.onState([_robot(playing: true, step: 0)], connected: true);
      await surfaces.onSessionEnd();
      expect(live.calls.last, 'end');
    });

    test('the watch gets the status only when on, and a stop from it runs only while on and fresh', () async {
      var now = t0;
      final watch = _FakeWatch();
      final surfaces = ExternalSurfaces(alerts: _FakeAlerts(), liveActivity: _FakeLive(), watch: watch, clock: () => now);
      addTearDown(surfaces.dispose);
      var stops = 0;
      surfaces.listenForWatchStop(() => stops++);
      expect(watch.onStop!(now), isFalse);
      expect(stops, 0, reason: 'off');
      surfaces.setWatch(true);
      await surfaces.onState([_robot(playing: true, step: 2)], connected: true);
      expect(watch.sent.single['status'], 'running');
      expect(watch.sent.single['connected'], true);
      expect(watch.onStop!(now.subtract(const Duration(minutes: 5))), isFalse);
      expect(stops, 0, reason: 'too old');
      expect(watch.onStop!(now), isTrue);
      expect(stops, 1);
      await surfaces.onSessionEnd();
      expect(watch.sent.last['connected'], false);
    });
  });

  group('the feature contract', () {
    final json = jsonDecode(File('docs/ios_feature_contract.json').readAsStringSync()) as Map<String, dynamic>;

    test('whatever reaches out of the app starts off', () {
      for (final section in ['jobAlerts', 'liveActivity', 'voice', 'watchCompanion']) {
        expect((json[section] as Map)['enabledByDefault'], isFalse, reason: section);
      }
      expect(JobAlertsContract.enabledByDefault, isFalse);
      expect(LiveActivityContract.enabledByDefault, isFalse);
      expect(VoiceContract.enabledByDefault, isFalse);
      expect(WatchCompanionContract.enabledByDefault, isFalse);
      expect(VoiceContract.onDeviceOnly, isTrue, reason: 'the audio stays on the phone unless the person allows more');
    });

    test('the generated constants carry the values of the JSON', () {
      expect(DiagnosticsContract.probeCount, (json['diagnostics'] as Map)['probeCount']);
      expect(JobAlertsContract.maxPerMinute, (json['jobAlerts'] as Map)['maxPerMinute']);
      expect(LiveActivityContract.minUpdateGapMs, (json['liveActivity'] as Map)['minUpdateGapMs']);
      expect(EcosystemContract.refreshMinIntervalMs, (json['ecosystem'] as Map)['refreshMinIntervalMs']);
    });

    test('the link limits come from the contract shared with the Android app', () {
      final shared = jsonDecode(File('docs/robot_command_contract.json').readAsStringSync()) as Map<String, dynamic>;
      final link = shared['linkHealth'] as Map<String, dynamic>;
      expect(RobotCommandContract.linkGoodRttMs, link['goodRttMs']);
      expect(RobotCommandContract.linkPoorRttMs, link['poorRttMs']);
      expect(RobotCommandContract.linkBlockRttMs, link['blockRttMs']);
      expect(RobotCommandContract.linkLostAfterMs, link['lostAfterMs']);
      expect(RobotCommandContract.linkSampleWindow, link['sampleWindow']);
    });
  });
}
