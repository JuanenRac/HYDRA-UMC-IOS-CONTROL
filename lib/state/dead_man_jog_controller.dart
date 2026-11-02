// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/dead_man_jog_controller.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's viewmodel/DeadManJogController.kt. What the screen sees of the continuous jog and of
// the health of the link: the switches (both start from the contract, the jog OFF), the robots whose control is held, the
// level and the round-trip time of the link. It joins the rules (util/dead_man_jog.dart), the runner that talks to the
// server and the link meter (util/link_health.dart); it holds no widget and says things only through the functions it is
// given, so it is tested on the Dart VM.
//
// Whatever ends a session (release, link lost, STOP, screen left) stops the axis through the runner; this class never
// leaves a control marked as held after the session ended.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/contract_v2.dart';
import '../models/robot_command_contract.dart';
import '../network/dead_man_jog_runner.dart';
import '../network/hydra_api_client.dart';
import '../util/dead_man_jog.dart';
import '../util/link_health.dart';
import 'hydra_error.dart';
import 'robot_command_repository.dart';

class DeadManJogController extends ChangeNotifier {
  DeadManJogController({
    required CommandPoster poster,
    required this.pinger,
    required this.situation,
    required this.say,
    DeadManSettings settings = const DeadManSettings(),
    int Function()? clock,
    LinkHealth? link,
    this.probeInterval = const Duration(milliseconds: RobotCommandContract.linkProbeIntervalMs),
  }) : link = link ?? LinkHealth() {
    runner = DeadManJogRunner(
      poster: poster,
      settings: settings,
      clock: clock,
      linkAllows: () => !_linkBlocks(),
      onRoundTrip: (rtt) {
        this.link.record(rtt);
        notifyListeners();
      },
      onEnded: (robotId, reason, stopConfirmed) {
        _held.remove(robotId);
        final error = _endError(reason, stopConfirmed);
        if (error != null) say(error);
        notifyListeners();
      },
    );
  }

  /// One small request to the server; returns its round-trip time in ms and throws when nobody answers.
  final Future<int> Function() pinger;

  /// What the app knows of the robot, to decide whether the jog may start.
  final DeadManSituation Function(dynamic robotId, {required bool switchedOn, required bool alreadyRunning, required bool linkBlocks, required bool serverSupports}) situation;

  /// Tells the person something (null clears it).
  final void Function(HydraError? error) say;

  final Duration probeInterval;
  final LinkHealth link;
  late final DeadManJogRunner runner;

  /// The continuous jog itself: off until the person turns it on.
  bool enabled = RobotCommandContract.deadManEnabledByDefault;

  /// Whether a bad or lost link stops (and refuses) the continuous jog: on by default.
  bool blockOnBadLink = RobotCommandContract.linkBlockJogOnBadLinkDefault;

  /// Whether the link indicator is shown on the Control screen.
  bool indicator = RobotCommandContract.linkIndicatorEnabledByDefault;

  /// Speed of the continuous jog, in the range of the contract.
  double velocity = RobotCommandContract.deadManVelocityDefault.toDouble();

  /// False once the server answered that it does not know the continuous-jog commands.
  bool serverSupports = true;

  final Set<dynamic> _held = {};

  /// The robots whose control is held (the start may still be on the wire).
  Set<dynamic> get held => Set.unmodifiable(_held);

  LinkLevel get linkLevel => link.level;
  int? get linkRttMs => link.lastMs;

  Timer? _probe;
  bool _probing = false;
  bool _disposed = false;

  bool _linkBlocks() => blockOnBadLink && link.blocksJog;

  /// The first reason not to start for [robotId] now, [DeadManBlock.none] when it may.
  DeadManBlock blockOf(dynamic robotId) => deadManBlockOf(situation(
        robotId,
        switchedOn: enabled,
        alreadyRunning: _held.contains(robotId),
        linkBlocks: _linkBlocks(),
        serverSupports: serverSupports,
      ));

  void setVelocity(double value) {
    velocity = value.clamp(RobotCommandContract.deadManVelocityMin.toDouble(), RobotCommandContract.deadManVelocityMax.toDouble()).toDouble();
    notifyListeners();
  }

  /// The control for [axis] of [target] was pressed; [direction] is +1 or -1. Nothing moves if a rule refuses.
  Future<void> press(dynamic robotId, String target, String axis, int direction) async {
    final block = blockOf(robotId);
    if (block != DeadManBlock.none) {
      say(HydraError(HydraErrorKind.deadManBlocked, {'block': block.name}));
      return;
    }
    _held.add(robotId);
    notifyListeners();
    final signed = (direction < 0 ? -1 : 1) * velocity;
    try {
      await runner.start(robotId, target, axis, signed);
      // The finger left while the start was on the wire: stop at once instead of holding a jog nobody holds.
      if (!_held.contains(robotId)) runner.release(robotId);
      say(null);
    } catch (e) {
      _held.remove(robotId);
      if (e is HydraApiException && isUnknownCommandAnswer(e.statusCode, e.code, e.serverMessage)) serverSupports = false;
      say(_startError(e));
      notifyListeners();
    }
  }

  /// The control was released (or the finger slid off it).
  void release(dynamic robotId) {
    final wasHeld = _held.remove(robotId);
    runner.release(robotId); // the stop goes out first
    // Told after the current frame work: a button that is being removed from the tree releases from its dispose.
    if (wasHeld) scheduleMicrotask(notifyListeners);
  }

  /// Stops every held jog now: a STOP is going out, the screen was left, the connection was lost.
  void interrupt() {
    if (_held.isEmpty && !runner.anyRunning) return;
    _held.clear();
    runner.interrupt();
    scheduleMicrotask(notifyListeners);
  }

  HydraError _startError(Object e) {
    if (e is HydraApiException) {
      return HydraError(HydraErrorKind.txError, {'command': RobotCommandContract.jogStart, 'error': e.serverMessage ?? e.message});
    }
    return HydraError(HydraErrorKind.txError, {'command': RobotCommandContract.jogStart, 'error': '$e'});
  }

  HydraError? _endError(DeadManEnd reason, bool stopConfirmed) {
    if (!stopConfirmed) return const HydraError(HydraErrorKind.deadManStopNotConfirmed);
    return switch (reason) {
      DeadManEnd.released || DeadManEnd.interrupted => null,
      _ => HydraError(HydraErrorKind.deadManEnded, {'reason': reason.name}),
    };
  }

  /// Measures the link while [active] says so and while the indicator or the jog is switched on; ends by itself when either
  /// stops being true, and [ensureProbe] starts it again. A probe that gets no answer counts as a failure.
  void ensureProbe(bool Function() active) {
    if (_probe != null || !active() || !(indicator || enabled)) return;
    _probe = Timer.periodic(probeInterval, (timer) {
      if (!active() || !(indicator || enabled)) {
        timer.cancel();
        _probe = null;
        if (!active()) link.reset();
        _notify();
        return;
      }
      unawaited(_probeOnce());
    });
    unawaited(_probeOnce());
  }

  Future<void> _probeOnce() async {
    if (_probing) return;
    _probing = true;
    try {
      link.record(await pinger());
    } catch (_) {
      link.recordFailure();
    } finally {
      _probing = false;
    }
    _notify();
  }

  void stopProbe() {
    _probe?.cancel();
    _probe = null;
    link.reset();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _probe?.cancel();
    runner.interrupt();
    super.dispose();
  }
}
