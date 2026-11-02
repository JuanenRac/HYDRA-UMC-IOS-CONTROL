// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/dead_man_jog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's util/DeadManJog.kt: the rules of the continuous jog. An axis moves while the
// control is held, the app sends a heartbeat all the while, and the movement ends as soon as the heartbeat cannot be
// trusted. This file holds only the rules (no network, no screen): when the app refuses to start, how the speed is
// bounded and the watchdog that decides the link is gone. Every number comes from docs/robot_command_contract.json
// through the generated RobotCommandContract, so none is tuned here.
// =============================================================================

import '../models/robot_command_contract.dart';

/// The timings and limits of one session; the defaults are the contract's.
class DeadManSettings {
  final int heartbeatMs;
  final int serverTimeoutMs;
  final int maxMissedHeartbeats;
  final int maxHoldMs;
  final int stopAttempts;
  final int stopRetryPauseMs;
  final int stopTimeoutMs;
  final int velocityMin;
  final int velocityMax;

  const DeadManSettings({
    this.heartbeatMs = RobotCommandContract.deadManHeartbeatMs,
    this.serverTimeoutMs = RobotCommandContract.deadManServerTimeoutMs,
    this.maxMissedHeartbeats = RobotCommandContract.deadManMaxMissedHeartbeats,
    this.maxHoldMs = RobotCommandContract.deadManMaxHoldMs,
    this.stopAttempts = RobotCommandContract.deadManStopAttempts,
    this.stopRetryPauseMs = RobotCommandContract.deadManStopRetryPauseMs,
    this.stopTimeoutMs = RobotCommandContract.deadManStopTimeoutMs,
    this.velocityMin = RobotCommandContract.deadManVelocityMin,
    this.velocityMax = RobotCommandContract.deadManVelocityMax,
  })  : assert(heartbeatMs > 0 && serverTimeoutMs > heartbeatMs, 'the server timeout must be longer than the heartbeat'),
        assert(maxMissedHeartbeats >= 1 && maxHoldMs > 0 && stopAttempts >= 1, 'the limits must be positive'),
        assert(velocityMin >= 1 && velocityMin <= velocityMax, 'the speed range must be valid');
}

/// Why the app does not start the continuous jog; [none] means it may.
enum DeadManBlock {
  none,
  off,
  notConnected,
  offline,
  safeMode,
  moving,
  stopPending,
  notArmed,
  role,
  badLink,
  alreadyRunning,
  notSupported,
}

/// What the app knows at the moment the control is pressed.
class DeadManSituation {
  final bool switchedOn;
  final bool connected;
  final bool robotOnline;

  /// False when the robot is in safe mode (the server refuses everything but STOP then).
  final bool robotEnabled;

  /// A trajectory is playing (paused or not): a jog would fight its setpoint.
  final bool robotPlaying;

  /// The global STOP is being sent or has not been confirmed.
  final bool stopInProgress;

  /// The administrator requires the jog to be armed and it is not.
  final bool needsArming;

  /// The role of the session (`admin`, `operator`) or null when it cannot be read; the server checks it anyway.
  final String? role;

  /// The link health blocks the jog (switch on and the link is bad or lost).
  final bool linkBlocks;

  /// A continuous jog of this robot is already held.
  final bool alreadyRunning;

  /// False once the server answered that it does not know the commands.
  final bool serverSupports;

  const DeadManSituation({
    required this.switchedOn,
    required this.connected,
    required this.robotOnline,
    required this.robotEnabled,
    required this.robotPlaying,
    required this.stopInProgress,
    required this.needsArming,
    required this.role,
    required this.linkBlocks,
    required this.alreadyRunning,
    required this.serverSupports,
  });
}

/// Who may move a robot: an operator or an administrator (the server checks it again). Null = the role is not known.
bool deadManRoleAllowed(String? role) => role == null || role == 'admin' || role == 'operator';

/// The first reason not to start, in the order a person can fix them; [DeadManBlock.none] when there is none.
DeadManBlock deadManBlockOf(DeadManSituation s) {
  if (!s.switchedOn) return DeadManBlock.off;
  if (!s.connected) return DeadManBlock.notConnected;
  if (!s.serverSupports) return DeadManBlock.notSupported;
  if (!deadManRoleAllowed(s.role)) return DeadManBlock.role;
  if (!s.robotOnline) return DeadManBlock.offline;
  if (!s.robotEnabled) return DeadManBlock.safeMode;
  if (s.stopInProgress) return DeadManBlock.stopPending;
  if (s.robotPlaying) return DeadManBlock.moving;
  if (s.needsArming) return DeadManBlock.notArmed;
  if (s.alreadyRunning) return DeadManBlock.alreadyRunning;
  if (s.linkBlocks) return DeadManBlock.badLink;
  return DeadManBlock.none;
}

/// Why a session ended.
enum DeadManEnd {
  /// The control was released.
  released,

  /// Heartbeats failed or went unanswered for too long: the app stopped the axis by itself.
  linkLost,

  /// The hold passed the longest time allowed.
  tooLong,

  /// The link health became bad while the control was held.
  badLink,

  /// The server refused a heartbeat (the session no longer exists there, the robot is reserved by another...).
  serverRefused,

  /// The app left the screen, lost the connection or a STOP was sent.
  interrupted,
}

/// The velocity with its magnitude kept inside the range of the contract; the sign is the direction and is kept.
/// A value that is not a number, or zero, becomes the smallest speed forwards.
double clampDeadManVelocity(double velocity, [DeadManSettings settings = const DeadManSettings()]) {
  if (velocity.isNaN || velocity == 0.0) return settings.velocityMin.toDouble();
  final magnitude = velocity.abs().clamp(settings.velocityMin.toDouble(), settings.velocityMax.toDouble()).toDouble();
  return velocity < 0 ? -magnitude : magnitude;
}

/// Decides, from the answers to the heartbeats, whether the link can still be trusted. It is fed with the clock of the
/// phone (milliseconds); it never sleeps and sends nothing. The server stops the axis by itself after
/// [DeadManSettings.serverTimeoutMs] without a heartbeat, so the app gives the link up before that.
class DeadManWatchdog {
  DeadManWatchdog(this.settings, this._clock)
      : _startedAt = _clock(),
        _lastAckAt = _clock();

  final DeadManSettings settings;
  final int Function() _clock;
  final int _startedAt;
  int _lastAckAt;
  int _missed = 0;

  /// A heartbeat (or the start) was answered.
  void acked() {
    _lastAckAt = _clock();
    _missed = 0;
  }

  /// A heartbeat failed or timed out.
  void missed() => _missed++;

  int get missedInARow => _missed;

  /// The reason to stop now, or null while the link can be trusted.
  DeadManEnd? verdict() {
    final now = _clock();
    if (_missed >= settings.maxMissedHeartbeats) return DeadManEnd.linkLost;
    if (now - _lastAckAt > settings.serverTimeoutMs) return DeadManEnd.linkLost;
    if (now - _startedAt > settings.maxHoldMs) return DeadManEnd.tooLong;
    return null;
  }
}
