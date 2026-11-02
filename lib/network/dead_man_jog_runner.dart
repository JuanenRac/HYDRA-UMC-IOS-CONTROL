// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/dead_man_jog_runner.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's network/DeadManJogRunner.kt. Holds a continuous jog: `jogStart`, then a
// `jogHeartbeat` every heartbeat period while the control is held, then `jogStop`. The axis must never keep moving on
// its own, so the runner ends the session by itself, with a stop sent as urgently as a STOP (retried), as soon as the
// watchdog stops trusting the link, the hold is too long, the link health blocks it, the server refuses a heartbeat, or
// [interrupt] is called (the screen was left, a STOP was sent). The server does the same on its side when no heartbeat
// arrives for the time of the contract.
//
// It holds no widget and sends through a [CommandPoster], so it is tested on the Dart VM with a fake server and a fake
// clock.
// =============================================================================

import 'dart:async';

import '../models/robot_command_contract.dart';
import '../state/robot_command_repository.dart';
import '../util/dead_man_jog.dart';
import 'hydra_api_client.dart';

class DeadManJogRunner {
  DeadManJogRunner({
    required this.poster,
    this.settings = const DeadManSettings(),
    int Function()? clock,
    this.linkAllows,
    this.onRoundTrip,
    this.onEnded,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CommandPoster poster;
  final DeadManSettings settings;
  final int Function() _clock;

  /// True while the link health lets the jog go on (checked at every heartbeat).
  final bool Function()? linkAllows;

  /// A heartbeat was answered after this many ms: the link health takes it as a sample.
  final void Function(int rttMs)? onRoundTrip;

  /// A session ended; [stopConfirmed] tells whether the server answered the stop (if not, its own timeout will stop the axis).
  final void Function(dynamic robotId, DeadManEnd reason, bool stopConfirmed)? onEnded;

  final Map<dynamic, _Session> _sessions = {};
  int _counter = 0;

  bool isRunning(dynamic robotId) => _sessions[robotId]?.ending == false;

  bool get anyRunning => _sessions.values.any((s) => !s.ending);

  Map<String, dynamic> _payload(String command, Map<String, dynamic> params) => {'command': command, 'params': params};

  /// Sends `jogStart` and, when the server accepts it, begins the heartbeat. The failure of the start is thrown to the
  /// caller (nothing moves then); a start that was answered but not understood is the caller's to explain.
  Future<void> start(dynamic robotId, String target, String axis, double velocity) async {
    if (isRunning(robotId)) return;
    final sessionId = 'dm-${++_counter}-${_clock()}';
    final clamped = clampDeadManVelocity(velocity, settings);
    final params = <String, dynamic>{
      'sessionId': sessionId,
      'target': target,
      'axis': axis,
      'velocity': clamped,
      'heartbeatMs': settings.heartbeatMs,
      'timeoutMs': settings.serverTimeoutMs,
    };
    final session = _Session(robotId, sessionId);
    // Registered before the request leaves: a release or an interruption while the start is on the wire still finds it
    // and sends the stop, because the server may have taken the start already.
    _sessions[robotId] = session;
    try {
      await poster(robotId, _payload(RobotCommandContract.jogStart, params), urgent: true, ifMatch: null)
          .timeout(Duration(milliseconds: settings.serverTimeoutMs * 5));
    } catch (_) {
      // The start failed: when no release came meanwhile there is nothing to stop; one that came is already ending.
      if (!session.ending) _sessions.remove(robotId);
      rethrow;
    }
    if (session.ending) return; // ended while the start was on the wire: its stop is already going out
    final watchdog = DeadManWatchdog(settings, _clock);
    unawaited(_heartbeats(session, watchdog));
  }

  /// The control was released.
  void release(dynamic robotId) => _end(robotId, DeadManEnd.released);

  /// The screen was left, the connection dropped or a STOP is going out: every session ends and its axis is stopped.
  void interrupt() {
    final ids = [for (final s in _sessions.values) if (!s.ending) s.robotId];
    for (final id in ids) {
      _end(id, DeadManEnd.interrupted);
    }
  }

  void _end(dynamic robotId, DeadManEnd reason) {
    final session = _sessions[robotId];
    if (session == null || session.ending) return;
    session.ending = true;
    unawaited(_stopAndReport(session, reason));
  }

  Future<void> _stopAndReport(_Session session, DeadManEnd reason) async {
    final confirmed = await _sendStop(session);
    if (identical(_sessions[session.robotId], session)) _sessions.remove(session.robotId);
    onEnded?.call(session.robotId, reason, confirmed);
  }

  Future<bool> _sendStop(_Session session) async {
    final stop = _payload(RobotCommandContract.jogStop, {'sessionId': session.id});
    for (var attempt = 0; attempt < settings.stopAttempts; attempt++) {
      try {
        await poster(session.robotId, {...stop, 'params': {...(stop['params'] as Map<String, dynamic>)}}, urgent: true, ifMatch: null)
            .timeout(Duration(milliseconds: settings.stopTimeoutMs));
        return true;
      } catch (_) {
        // tried again below
      }
      if (attempt < settings.stopAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: settings.stopRetryPauseMs));
      }
    }
    return false;
  }

  Future<void> _heartbeats(_Session session, DeadManWatchdog watchdog) async {
    var sequence = 0;
    while (!session.ending) {
      final startedAt = _clock();
      final params = <String, dynamic>{'sessionId': session.id, 'sequence': ++sequence};
      var refused = false;
      try {
        await poster(session.robotId, _payload(RobotCommandContract.jogHeartbeat, params), urgent: true, ifMatch: null)
            .timeout(Duration(milliseconds: settings.serverTimeoutMs - settings.heartbeatMs));
        watchdog.acked();
        onRoundTrip?.call(_clock() - startedAt);
      } on HydraApiException catch (e) {
        // An answer of the server that is an error: the session is not (or no longer) accepted there.
        final code = e.statusCode;
        if (code != null && code >= 400 && code <= 499 && code != 408 && code != 429) {
          refused = true;
        } else {
          watchdog.missed();
        }
      } catch (_) {
        watchdog.missed();
      }
      if (session.ending) return; // ended meanwhile (release, STOP): its stop is already going out
      final DeadManEnd? verdict;
      if (refused) {
        verdict = DeadManEnd.serverRefused;
      } else {
        verdict = watchdog.verdict() ?? ((linkAllows?.call() ?? true) ? null : DeadManEnd.badLink);
      }
      if (verdict != null) {
        _end(session.robotId, verdict);
        return;
      }
      final spent = _clock() - startedAt;
      final wait = settings.heartbeatMs - spent;
      await Future<void>.delayed(Duration(milliseconds: wait < 1 ? 1 : wait));
    }
  }
}

class _Session {
  _Session(this.robotId, this.id);
  final dynamic robotId;
  final String id;
  bool ending = false;
}
