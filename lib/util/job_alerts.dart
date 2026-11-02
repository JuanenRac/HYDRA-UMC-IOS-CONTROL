// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/job_alerts.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Decides which local notifications the phone shows from the changes of the robots it is told about: a job that
// finished, a robot that went offline or into safe mode, a connection that stayed lost. It holds no clock and no
// notification system of its own (the caller gives the time and shows what comes out), so it is tested on the Dart VM.
// Notifications are rationed: the same alert for the same robot at most once per dedupe window, never two closer than
// the minimum gap, never more than the maximum per minute, so a burst never floods the lock screen.
// A notification never moves a robot and never carries a command.
// =============================================================================

import '../models/hydra_state.dart';
import '../models/ios_feature_contract.dart';

/// What the app knows of one robot, enough to see what changed. Plain data: no reference to the live state.
class RobotSnapshot {
  final String id;
  final String name;
  final bool online;
  final bool enabled;
  final bool playing;
  final bool paused;
  final bool finished;
  final int activeStep;
  final int totalSteps;

  const RobotSnapshot({
    required this.id,
    required this.name,
    this.online = true,
    this.enabled = true,
    this.playing = false,
    this.paused = false,
    this.finished = false,
    this.activeStep = -1,
    this.totalSteps = 0,
  });

  factory RobotSnapshot.of(RobotView robot) {
    final pb = robot.playbackState;
    final step = pb['activeStep'];
    final points = robot.raw['recordedPoints'];
    return RobotSnapshot(
      id: '${robot.id}',
      name: robot.name,
      online: robot.online,
      enabled: robot.isEnabled,
      playing: robot.isPlaying,
      paused: robot.isPaused,
      finished: (pb['isFinished'] ?? pb['finished']) == true,
      activeStep: step is num ? step.toInt() : -1,
      totalSteps: points is List ? points.length : 0,
    );
  }
}

enum AlertKind { jobFinished, robotOffline, robotSafeMode, connectionLost }

class AlertEvent {
  final AlertKind kind;
  final String? robotId;
  final String? robotName;
  const AlertEvent(this.kind, {this.robotId, this.robotName});

  String get key => '${kind.name}:${robotId ?? ''}';
}

class JobAlertDetector {
  JobAlertDetector({
    this.dedupeWindow = const Duration(milliseconds: JobAlertsContract.dedupeWindowMs),
    this.minGap = const Duration(milliseconds: JobAlertsContract.minGapMs),
    this.maxPerMinute = JobAlertsContract.maxPerMinute,
    this.connectionLostAfter = const Duration(milliseconds: JobAlertsContract.connectionLostAfterMs),
  });

  final Duration dedupeWindow;
  final Duration minGap;
  final int maxPerMinute;
  final Duration connectionLostAfter;

  Map<String, RobotSnapshot>? _previous;
  final Map<String, DateTime> _lastByKey = {};
  final List<DateTime> _shown = [];
  DateTime? _lostSince;
  bool _lostReported = false;
  bool _wasConnected = false;

  /// Forgets what it saw (a new session): the first reading after this only sets the baseline.
  void reset() {
    _previous = null;
    _lastByKey.clear();
    _shown.clear();
    _lostSince = null;
    _lostReported = false;
    _wasConnected = false;
  }

  /// Compares [robots] with the previous reading and returns the alerts to show now. The first reading only sets the
  /// baseline, so opening the app on a finished job does not notify.
  List<AlertEvent> update(List<RobotSnapshot> robots, DateTime now) {
    final previous = _previous;
    _previous = {for (final r in robots) r.id: r};
    if (previous == null) return const [];
    final events = <AlertEvent>[];
    for (final robot in robots) {
      final before = previous[robot.id];
      if (before == null) continue;
      if (before.playing && !robot.playing && robot.finished) {
        events.add(AlertEvent(AlertKind.jobFinished, robotId: robot.id, robotName: robot.name));
      }
      if (before.online && !robot.online) {
        events.add(AlertEvent(AlertKind.robotOffline, robotId: robot.id, robotName: robot.name));
      }
      if (before.enabled && !robot.enabled) {
        events.add(AlertEvent(AlertKind.robotSafeMode, robotId: robot.id, robotName: robot.name));
      }
    }
    return _ration(events, now);
  }

  /// Tells whether the link to the server is up. A link that stays down for [connectionLostAfter] gives one
  /// `connectionLost` alert; it is armed again when the link comes back. A link that was never up in this session
  /// (the app just opened, the person is signing in) is not a lost one.
  List<AlertEvent> linkUpdate({required bool connected, required DateTime now}) {
    if (connected) {
      _wasConnected = true;
      _lostSince = null;
      _lostReported = false;
      return const [];
    }
    if (!_wasConnected) return const []; // never up in this session: nothing was lost
    _lostSince ??= now;
    if (_lostReported || now.difference(_lostSince!) < connectionLostAfter) return const [];
    _lostReported = true;
    return _ration(const [AlertEvent(AlertKind.connectionLost)], now);
  }

  List<AlertEvent> _ration(List<AlertEvent> events, DateTime now) {
    final out = <AlertEvent>[];
    _shown.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    // The gap is kept against the alerts of earlier readings; alerts of the same reading go out together.
    final lastEarlier = _shown.isEmpty ? null : _shown.last;
    for (final event in events) {
      final last = _lastByKey[event.key];
      if (last != null && now.difference(last) < dedupeWindow) continue;
      if (lastEarlier != null && now.difference(lastEarlier) < minGap) continue;
      if (_shown.length >= maxPerMinute) continue;
      _lastByKey[event.key] = now;
      _shown.add(now);
      out.add(event);
    }
    return out;
  }
}
