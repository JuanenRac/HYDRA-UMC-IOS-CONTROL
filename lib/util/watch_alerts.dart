// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/watch_alerts.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's wear/WatchAlerts.kt: the alerts the phone pushes to the watch, what is worth one,
// and how many. It looks at the phone's view of the plant over time and says which changes deserve an alert on the
// wrist: the connection to the server lost (and back), a robot that went offline or into safe mode, a STOP that the server
// did not confirm (and the one that was). It holds no network and no clock besides the one it is given.
//
// Rationing, so a burst never floods the wrist: the same event is not repeated within the dedupe window; the rest are
// spaced by a minimum gap and capped per minute. A CRITICAL alert is never held back by the gap or the cap (only by the
// dedupe), because it is the one that must arrive. The numbers come from docs/robot_command_contract.json.
// =============================================================================

import '../models/robot_command_contract.dart';

/// How serious an alert is; the watch vibrates by it (critical stays until opened).
enum WatchAlertSeverity { critical, warning, info }

/// The message the watch accepts: a severity and 1 to [RobotCommandContract.watchAlertsMessageMax] characters.
class WatchAlert {
  final WatchAlertSeverity severity;
  final String message;

  WatchAlert(this.severity, this.message) {
    if (message.trim().isEmpty || message.length > RobotCommandContract.watchAlertsMessageMax) {
      throw ArgumentError('an alert message has 1 to ${RobotCommandContract.watchAlertsMessageMax} characters');
    }
  }

  /// The alert for [message], cut with an ellipsis when it is too long and never blank.
  factory WatchAlert.of(WatchAlertSeverity severity, String message) {
    const max = RobotCommandContract.watchAlertsMessageMax;
    final text = message.trim().isEmpty ? '!' : message.trim();
    return WatchAlert(severity, text.length > max ? '${text.substring(0, max - 1)}…' : text);
  }

  Map<String, Object> toMap() => {'type': 'alert', 'severity': severity.name.toUpperCase(), 'message': message};
}

/// What the phone knows about one robot at the moment of an observation.
class WatchAlertRobot {
  final String id;
  final String name;
  final bool online;
  final bool enabled;
  final bool playing;
  const WatchAlertRobot(this.id, this.name, this.online, this.enabled, this.playing);
}

/// The progress of the global STOP, reduced to what matters here.
enum WatchAlertStop { none, sending, notConfirmed, done }

class WatchAlertInput {
  final bool connected;
  final List<WatchAlertRobot> robots;
  final WatchAlertStop stop;
  const WatchAlertInput({required this.connected, required this.robots, required this.stop});
}

/// What happened, without words: the app turns it into a sentence in the language of the phone.
enum WatchAlertKind { connectionLost, connectionRestored, robotOffline, robotSafeMode, stopNotConfirmed, stopConfirmed }

class WatchAlertEvent {
  final WatchAlertKind kind;
  final WatchAlertSeverity severity;
  final String? robotName;
  final String key;
  const WatchAlertEvent(this.kind, this.severity, this.key, [this.robotName]);
}

class WatchAlertRules {
  WatchAlertRules({
    DateTime Function()? clock,
    this.dedupeWindowMs = RobotCommandContract.watchAlertsDedupeWindowMs,
    this.minGapMs = RobotCommandContract.watchAlertsMinGapMs,
    this.maxPerMinute = RobotCommandContract.watchAlertsMaxPerMinute,
    this.connectionLostAfterMs = RobotCommandContract.watchAlertsConnectionLostAfterMs,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final int dedupeWindowMs;
  final int minGapMs;
  final int maxPerMinute;
  final int connectionLostAfterMs;

  bool _initialised = false;
  bool _everConnected = false;
  int? _lostSince;
  bool _lostAnnounced = false;
  bool _playingWhenLost = false;
  Map<String, WatchAlertRobot> _robots = const {};
  WatchAlertStop _stop = WatchAlertStop.none;

  final Map<String, int> _lastSentByKey = {};
  final List<int> _sentAt = [];
  int? _lastSentAny;

  /// Forgets what it saw (a new session): the next observation only learns the starting point again.
  void reset() {
    _initialised = false;
    _everConnected = false;
    _lostSince = null;
    _lostAnnounced = false;
    _playingWhenLost = false;
    _robots = const {};
    _stop = WatchAlertStop.none;
    _lastSentByKey.clear();
    _sentAt.clear();
    _lastSentAny = null;
  }

  /// The events that deserve an alert now. Call it often (about once a second); the first call only learns the starting point.
  List<WatchAlertEvent> observe(WatchAlertInput input) {
    final now = _clock().millisecondsSinceEpoch;
    final found = <WatchAlertEvent>[];
    if (!_initialised) {
      _initialised = true;
      _everConnected = input.connected;
      _robots = {for (final r in input.robots) r.id: r};
      _stop = input.stop;
      return const [];
    }
    if (input.connected) {
      _everConnected = true;
      if (_lostAnnounced) {
        found.add(const WatchAlertEvent(WatchAlertKind.connectionRestored, WatchAlertSeverity.info, 'restored'));
      }
      _lostSince = null;
      _lostAnnounced = false;
      final current = {for (final r in input.robots) r.id: r};
      for (final entry in _robots.entries) {
        final before = entry.value;
        final after = current[entry.key];
        if (after == null) continue;
        if (before.online && !after.online) {
          final severity = before.playing ? WatchAlertSeverity.critical : WatchAlertSeverity.warning;
          found.add(WatchAlertEvent(WatchAlertKind.robotOffline, severity, 'offline:${entry.key}', after.name));
        } else if (after.online && before.enabled && !after.enabled) {
          found.add(WatchAlertEvent(WatchAlertKind.robotSafeMode, WatchAlertSeverity.warning, 'safe:${entry.key}', after.name));
        }
      }
      _robots = current;
    } else if (_everConnected) {
      final since = _lostSince;
      if (since == null) {
        _lostSince = now;
        _playingWhenLost = _robots.values.any((r) => r.playing);
      } else if (!_lostAnnounced && now - since >= connectionLostAfterMs) {
        _lostAnnounced = true;
        found.add(WatchAlertEvent(
          WatchAlertKind.connectionLost,
          _playingWhenLost ? WatchAlertSeverity.critical : WatchAlertSeverity.warning,
          'lost',
        ));
      }
    }
    if (input.stop != _stop) {
      if (input.stop == WatchAlertStop.notConfirmed) {
        found.add(const WatchAlertEvent(WatchAlertKind.stopNotConfirmed, WatchAlertSeverity.critical, 'stop-not-confirmed'));
      } else if (input.stop == WatchAlertStop.done && (_stop == WatchAlertStop.sending || _stop == WatchAlertStop.notConfirmed)) {
        found.add(const WatchAlertEvent(WatchAlertKind.stopConfirmed, WatchAlertSeverity.info, 'stop-confirmed'));
      }
      _stop = input.stop;
    }
    return _ration(found, now);
  }

  List<WatchAlertEvent> _ration(List<WatchAlertEvent> events, int now) {
    final out = <WatchAlertEvent>[];
    // The gap is measured from the alerts of EARLIER observations: what was found together goes out together.
    final gapFrom = _lastSentAny;
    // The serious ones first, so they are never the ones that run into the cap (the order inside a level is kept).
    final ordered = [
      for (final severity in WatchAlertSeverity.values) ...events.where((e) => e.severity == severity),
    ];
    for (final event in ordered) {
      final last = _lastSentByKey[event.key];
      if (last != null && now - last < dedupeWindowMs) continue;
      if (event.severity != WatchAlertSeverity.critical) {
        _sentAt.removeWhere((t) => now - t >= 60000);
        if ((gapFrom != null && now - gapFrom < minGapMs) || _sentAt.length >= maxPerMinute) continue;
      }
      _lastSentByKey[event.key] = now;
      _lastSentAny = now;
      _sentAt.add(now);
      out.add(event);
    }
    return out;
  }
}
