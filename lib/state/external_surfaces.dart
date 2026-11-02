// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/external_surfaces.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Everything the app shows outside its own screens, driven by the state the view model already holds: the local
// notifications of a job, the Live Activity and the Apple Watch. Each one is off until the person turns it on in the
// settings (a notification needs the permission of the system too). The view model tells this class what it sees after
// every change; the class never reads the network and never sends a command to a robot.
//
// What runs here runs while the app does. The system suspends the app shortly after it leaves the screen, so a job
// that ends later is told by the push notifications of the server (the switch of the settings), not by these.
// =============================================================================

import 'dart:async';

import '../models/ios_feature_contract.dart';
import '../network/native_bridges.dart';
import '../util/job_alerts.dart';
import '../util/live_activity_model.dart';

class ExternalSurfaces {
  ExternalSurfaces({
    AlertsBridge? alerts,
    LiveActivityBridge? liveActivity,
    WatchBridge? watch,
    DateTime Function()? clock,
  })  : alertsBridge = alerts ?? MethodChannelAlertsBridge(),
        _liveActivity = liveActivity ?? MethodChannelLiveActivityBridge(),
        _watch = watch ?? MethodChannelWatchBridge(),
        _clock = clock ?? DateTime.now;

  final AlertsBridge alertsBridge;
  final LiveActivityBridge _liveActivity;
  final WatchBridge _watch;
  final DateTime Function() _clock;

  bool _jobAlerts = JobAlertsContract.enabledByDefault;
  bool _liveActivityOn = LiveActivityContract.enabledByDefault;
  bool _watchOn = WatchCompanionContract.enabledByDefault;

  bool get jobAlertsEnabled => _jobAlerts;
  bool get liveActivityEnabled => _liveActivityOn;
  bool get watchEnabled => _watchOn;

  final JobAlertDetector _detector = JobAlertDetector();
  final LiveActivityPlanner _planner = LiveActivityPlanner();
  final WatchStatusPlanner _watchPlanner = WatchStatusPlanner();
  final StreamController<AlertEvent> _alertEvents = StreamController<AlertEvent>.broadcast();
  Timer? _linkTimer;
  bool _connected = false;
  bool _liveActivityRefused = false;

  /// The alerts to show, one per event. The screen turns each into a sentence in the language of the app (this class
  /// has no language) and calls [showNotification].
  Stream<AlertEvent> get alerts => _alertEvents.stream;

  /// What the last state change gave: used by the tests and by the settings to tell the person why nothing shows.
  bool get liveActivityRefusedBySystem => _liveActivityRefused;

  Future<void> showNotification({required String id, required String title, required String body}) =>
      alertsBridge.show(id: id, title: title, body: body);

  /// Switches the notifications of a job. Turning them on asks the system for permission and stays off when refused;
  /// the answer says whether they are on.
  Future<bool> setJobAlerts(bool value) async {
    if (value) {
      final granted = await alertsBridge.requestPermission();
      if (!granted) {
        _jobAlerts = false;
        _stopLinkTimer();
        return false;
      }
      _detector.reset();
      _startLinkTimer();
    } else {
      _stopLinkTimer();
      _detector.reset();
    }
    _jobAlerts = value;
    return value;
  }

  /// Applies the saved choice without asking again (the permission was given when it was turned on).
  void restoreJobAlerts(bool value) {
    _jobAlerts = value;
    if (value) _startLinkTimer();
  }

  Future<void> setLiveActivity(bool value) async {
    _liveActivityOn = value;
    _liveActivityRefused = false;
    if (!value) await _runStep(_planner.stop());
  }

  void restoreLiveActivity(bool value) => _liveActivityOn = value;

  void setWatch(bool value) {
    _watchOn = value;
    _watchPlanner.reset();
  }

  void restoreWatch(bool value) => _watchOn = value;

  /// Reads the stop requests of the watch. [onStop] runs only for a fresh one, and only while the option is on; the answer
  /// (accepted or not) goes back to the watch, so it never shows a stop that nobody took.
  void listenForWatchStop(void Function() onStop) {
    _watch.listenForStop((requestedAt) {
      if (!_watchOn || !watchStopIsFresh(requestedAt, _clock())) return false;
      onStop();
      return true;
    });
  }

  /// The view model calls this after every change of the state it holds.
  Future<void> onState(List<RobotSnapshot> robots, {required bool connected}) async {
    _connected = connected;
    final now = _clock();
    if (_jobAlerts) {
      for (final event in [..._detector.update(robots, now), ..._detector.linkUpdate(connected: connected, now: now)]) {
        _alertEvents.add(event);
      }
    }
    if (!_liveActivityOn && !_watchOn) return;
    final content = SurfaceContent.choose(robots);
    if (_liveActivityOn) {
      await _runStep(_planner.next(connected ? content : null, now));
    }
    if (_watchOn) {
      final status = _watchPlanner.next(content: content, connected: connected, now: now);
      if (status != null) await _watch.sendStatus(status);
    }
  }

  /// The session ended: whatever is shown goes away at once and the detectors forget the session.
  Future<void> onSessionEnd() async {
    _detector.reset();
    _watchPlanner.reset();
    _connected = false;
    await _runStep(_planner.stop());
    if (_watchOn) {
      await _watch.sendStatus({'connected': false, 'robotName': '', 'status': SurfaceStatus.idle.name, 'step': 0, 'total': 0});
    }
  }

  Future<void> _runStep(ActivityStep step) async {
    final content = step.content;
    switch (step.action) {
      case ActivityAction.none:
        return;
      case ActivityAction.start:
        if (!await _liveActivity.isAvailable()) {
          _liveActivityRefused = true;
          _planner.stop(); // nothing was started: the next change may try again
          return;
        }
        if (!await _liveActivity.start(_withStale(content!.toMap()))) {
          _liveActivityRefused = true;
          _planner.stop();
        }
      case ActivityAction.update:
        await _liveActivity.update(_withStale(content!.toMap()));
      case ActivityAction.end:
        await _liveActivity.end(_withStale(content!.toMap()), dismissAfterSeconds: step.dismissAfterSeconds);
    }
  }

  // The system dims a Live Activity that nobody refreshed for this long (the app was suspended), so it never passes for live.
  static Map<String, Object> _withStale(Map<String, Object> content) =>
      {...content, 'staleAfterSeconds': LiveActivityContract.staleAfterSeconds};

  // The link timer: the state only changes when something arrives, and a lost connection is exactly when nothing does.
  void _startLinkTimer() {
    _linkTimer?.cancel();
    _linkTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_jobAlerts) return;
      for (final event in _detector.linkUpdate(connected: _connected, now: _clock())) {
        _alertEvents.add(event);
      }
    });
  }

  void _stopLinkTimer() {
    _linkTimer?.cancel();
    _linkTimer = null;
  }

  void dispose() {
    _stopLinkTimer();
    _alertEvents.close();
  }
}
