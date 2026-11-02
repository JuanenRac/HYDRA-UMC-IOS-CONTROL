// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/live_activity_model.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// What goes to the surfaces outside the app: the Live Activity (lock screen and Dynamic Island) and the Apple Watch.
// Both show the same small status: the robot, what it is doing and the step of its trajectory. This file chooses the
// robot to show, builds the content and decides when to start, update or end the activity so the system is not
// flooded; it holds no clock and no native call (the caller gives the time and does what comes out), so it is tested
// on the Dart VM. The native halves are ios/Runner/LiveActivityBridge.swift and ios/Runner/WatchBridge.swift.
// A status never carries a command and never moves a robot.
// =============================================================================

import '../models/ios_feature_contract.dart';
import 'job_alerts.dart';

/// What the robot is doing, as the native sides name it (the same words in the Swift code and the watch app).
enum SurfaceStatus { running, paused, finished, stopped, offline, safeMode, idle }

class SurfaceContent {
  final String robotName;
  final SurfaceStatus status;
  final int step;
  final int total;

  const SurfaceContent({required this.robotName, required this.status, this.step = 0, this.total = 0});

  /// The robot name cut to the limit of the contract (so a very long name never fills the Dynamic Island).
  static String shortName(String name, [int max = LiveActivityContract.nameMax]) {
    final trimmed = name.trim();
    final runes = trimmed.runes.toList();
    return runes.length <= max ? trimmed : '${String.fromCharCodes(runes.take(max - 1))}…';
  }

  /// The robot to show: the first one that is playing, else the first one with a job just finished, else null.
  static SurfaceContent? choose(List<RobotSnapshot> robots) {
    RobotSnapshot? pick;
    for (final r in robots) {
      if (r.playing) {
        pick = r;
        break;
      }
    }
    pick ??= robots.cast<RobotSnapshot?>().firstWhere((r) => r!.finished, orElse: () => null);
    return pick == null ? null : of(pick);
  }

  static SurfaceContent of(RobotSnapshot r) {
    final status = !r.online
        ? SurfaceStatus.offline
        : !r.enabled
            ? SurfaceStatus.safeMode
            : r.playing
                ? (r.paused ? SurfaceStatus.paused : SurfaceStatus.running)
                : r.finished
                    ? SurfaceStatus.finished
                    : SurfaceStatus.idle;
    // activeStep counts from 0 and is -1 when nothing plays: the step shown counts from 1, never beyond the total.
    final total = r.totalSteps < 0 ? 0 : r.totalSteps;
    var step = r.activeStep < 0 ? 0 : r.activeStep + 1;
    if (total > 0 && step > total) step = total;
    if (status == SurfaceStatus.finished) step = total;
    return SurfaceContent(robotName: shortName(r.name), status: status, step: step, total: total);
  }

  Map<String, Object> toMap() => {'robotName': robotName, 'status': status.name, 'step': step, 'total': total};

  @override
  bool operator ==(Object other) =>
      other is SurfaceContent &&
      other.robotName == robotName &&
      other.status == status &&
      other.step == step &&
      other.total == total;

  @override
  int get hashCode => Object.hash(robotName, status, step, total);
}

enum ActivityAction { none, start, update, end }

class ActivityStep {
  final ActivityAction action;
  final SurfaceContent? content;

  /// For [ActivityAction.end]: how long the system keeps the finished activity on the lock screen.
  final int dismissAfterSeconds;
  const ActivityStep(this.action, [this.content, this.dismissAfterSeconds = 0]);
}

/// The state machine of the Live Activity: it starts when a robot is playing, follows its steps at most once per
/// minimum gap, and ends when the job ends (kept on the lock screen for a while when it finished), when nothing is left
/// to show or when the session ends.
class LiveActivityPlanner {
  LiveActivityPlanner({
    this.minGap = const Duration(milliseconds: LiveActivityContract.minUpdateGapMs),
    this.endAfterFinished = const Duration(seconds: LiveActivityContract.endAfterFinishedSeconds),
  });

  final Duration minGap;
  final Duration endAfterFinished;

  SurfaceContent? _shown;
  DateTime? _lastSentAt;
  bool get active => _shown != null;

  /// The next step for [content] (null: nothing to show) at [now].
  ActivityStep next(SurfaceContent? content, DateTime now) {
    final shown = _shown;
    if (shown == null) {
      if (content == null || content.status != SurfaceStatus.running && content.status != SurfaceStatus.paused) {
        return const ActivityStep(ActivityAction.none);
      }
      _shown = content;
      _lastSentAt = now;
      return ActivityStep(ActivityAction.start, content);
    }
    if (content == null) {
      _shown = null;
      return ActivityStep(ActivityAction.end, shown, 0);
    }
    final over = content.status == SurfaceStatus.finished ||
        content.status == SurfaceStatus.stopped ||
        content.status == SurfaceStatus.idle ||
        content.status == SurfaceStatus.offline ||
        content.status == SurfaceStatus.safeMode;
    if (over) {
      _shown = null;
      final keep = content.status == SurfaceStatus.finished ? endAfterFinished.inSeconds : 0;
      return ActivityStep(ActivityAction.end, content, keep);
    }
    if (content == shown) return const ActivityStep(ActivityAction.none);
    // A change of status (pause, resume) goes out at once; the step counter waits for the gap.
    final statusChanged = content.status != shown.status || content.robotName != shown.robotName;
    final last = _lastSentAt;
    if (!statusChanged && last != null && now.difference(last) < minGap) return const ActivityStep(ActivityAction.none);
    _shown = content;
    _lastSentAt = now;
    return ActivityStep(ActivityAction.update, content);
  }

  /// The session ended or the option was turned off: whatever is shown goes away at once.
  ActivityStep stop() {
    final shown = _shown;
    _shown = null;
    return shown == null ? const ActivityStep(ActivityAction.none) : ActivityStep(ActivityAction.end, shown, 0);
  }
}

/// The status sent to the watch, at most once per minimum gap and only when it changed.
class WatchStatusPlanner {
  WatchStatusPlanner({this.minGap = const Duration(milliseconds: WatchCompanionContract.statusMinGapMs)});

  final Duration minGap;
  Map<String, Object>? _last;
  DateTime? _lastAt;

  /// The map to send, or null when nothing needs to go out now.
  Map<String, Object>? next({required SurfaceContent? content, required bool connected, required DateTime now}) {
    final map = <String, Object>{
      'connected': connected,
      'robotName': content?.robotName ?? '',
      'status': (content?.status ?? SurfaceStatus.idle).name,
      'step': content?.step ?? 0,
      'total': content?.total ?? 0,
    };
    final last = _last;
    if (last != null && _same(last, map)) return null;
    final changedKind = last == null || last['connected'] != map['connected'] || last['status'] != map['status'];
    if (!changedKind && _lastAt != null && now.difference(_lastAt!) < minGap) return null;
    _last = map;
    _lastAt = now;
    return map;
  }

  static bool _same(Map<String, Object> a, Map<String, Object> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  void reset() {
    _last = null;
    _lastAt = null;
  }
}

/// A stop asked for on the watch is only worth carrying out while it is fresh: one that waited longer than the limit is
/// dropped, so a request that sat in a queue never fires later.
bool watchStopIsFresh(DateTime requestedAt, DateTime now) =>
    !now.isBefore(requestedAt) && now.difference(requestedAt).inMilliseconds <= WatchCompanionContract.stopMaxAgeMs;
